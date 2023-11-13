ngx.log(ngx.STDERR, 'Loading crypter')

local ffi = require('ffi')

ffi.cdef [[
  typedef struct RustSlice {
    uint8_t *ptr;
    uintptr_t len;
    uintptr_t capacity;
  } RustSlice;

  typedef struct Slice {
    uint8_t *ptr;
    uintptr_t len;
  } Slice;

  void crypter_free_slice(struct RustSlice slice);
  struct RustSlice crypter_encrypt(struct Slice pass, struct Slice payload);
  struct RustSlice crypter_decrypt(struct Slice pass, struct Slice payload);
]]

local crypter = ffi.load('crypter')

-- Makes a Slice from a Lua string/bytearray
--
-- Parameters:
--    string: a Lua string/bytearray
--
-- Returns:
--    [
--      a Slice pointing to `string`
--      the original `string`
--    ]
-- TODO: Review this
local function make_slice(string)
  local slice = ffi.new('Slice')
  slice.ptr = ffi.cast('uint8_t *', string)
  slice.len = #string

  return { slice, string }
end

-- Takes a RustSlice and interns it into Lua and frees the memory held by Rust
--
-- Parameters:
--    rust_slice: an instance of RustSlice
--
-- Returns: a Lua string/bytearray
local function intern_slice(rust_slice)
  local string = ffi.string(rust_slice.ptr, rust_slice.len)
  crypter.crypter_free_slice(rust_slice)
  return string
end

-- Decodes a Lua string/bytearray into a `user`
--
-- Parameters:
--    string: a Lua string/bytearray representation of a user, \0 separated
--    ttl: the number of seconds the token should be valid for
--
-- Returns:
--    - {
--        age: number,
--        email: string,
--        given_name: string,
--        family_name: string,
--        picture: string,
--      }
--    - `nil` if the payload is invalid
local function string_to_user(string, ttl)
  local fields = {}
  local index = 1
  for i = 1, #string do
    if string.byte(string, i) == 0 then
      table.insert(fields, string.sub(string, index, i - 1))
      i = i + 1
      index = i
    end
  end
  table.insert(fields, string.sub(string, index))

  if not fields[1] then
    ngx.log(ngx.STDERR, 'Expiry missing')
    return nil
  end

  local age = tonumber(fields[1])
  if not age then
    ngx.log(ngx.STDERR, 'Maformed age')
    return nil
  end

  if ngx.time() - age > ttl then
    ngx.log(ngx.STDERR, 'Expired token')
    return nil
  end

  return {
    age = age,
    email = fields[2],
    given_name = fields[3],
    family_name = fields[4],
    picture = fields[5],
  }
end

-- TODO: Can we keep this hanging around like this?
local secret = make_slice('$TOKEN_SECRET')

local M = {}

-- Encrypts a `user` into a base64 encoded Lua string
--
-- Parameters:
--    user: {
--            email: string,
--            given_name: string,
--            family_name: string,
--            picture: string,
--          }
--
-- Returns:
--    - encrypted `user` as a base64 encoded Lua string
--    - `nil` if the encryption failed
M.encrypt_user = function(user)
  local payload_slice = make_slice(string.format(
    '%d\0%s\0%s\0%s\0%s',
    ngx.time(),
    user.email,
    user.given_name,
    user.family_name,
    user.picture
  ))

  local encrypted = crypter.crypter_encrypt(secret[1], payload_slice[1])
  if encrypted.ptr == nil then
    ngx.log(ngx.STDERR, 'Failed to encrypt user')
    return nil
  end

  return ngx.encode_base64(intern_slice(encrypted))
end

-- Tries to decrypt a user token from a base64 encoded Lua string
--
-- Parameters:
--    encoded: a base64 encoded representation of the encrypted payload
--    ttl: the number of seconds the token should be valid for
--
-- Returns:
--    - {
--        age: number,
--        email: string,
--        given_name: string,
--        family_name: string,
--        picture: string,
--      }
--    - `nil` if the token is missing or the decryption failed
M.decrypt_user = function(encoded, ttl)
  if not encoded or #encoded == 0 then
    return nil
  end

  local decoded = ngx.decode_base64(encoded)
  if not decoded then
    return nil
  end

  local decoded_slice = make_slice(decoded)
  local decrypted = crypter.crypter_decrypt(secret[1], decoded_slice[1])
  if decrypted.ptr == nil then
    return nil
  end

  return string_to_user(intern_slice(decrypted), ttl)
end

return M
