local auther = {
  _VERSION = "0.0.1"
}

local ffi = require('ffi')

ffi.cdef([[
typedef struct CrypterRustSlice {
  uint8_t *ptr;
  uintptr_t len;
  uintptr_t capacity;
} CrypterRustSlice;

typedef struct CrypterCSlice {
  uint8_t *ptr;
  uintptr_t len;
} CrypterCSlice;

void crypter_free_slice(struct CrypterRustSlice slice);
struct CrypterRustSlice crypter_encrypt(struct CrypterCSlice pass, struct CrypterCSlice payload);
struct CrypterRustSlice crypter_decrypt(struct CrypterCSlice pass, struct CrypterCSlice payload);
]])

local crypter = ffi.load("crypter")

local function str_to_slice(text)
  local slice = ffi.new("CrypterCSlice")

  slice.ptr = ffi.new('uint8_t[?]', #text)
  slice.len = #text
  ffi.copy(slice.ptr, text)

  return slice
end

local function slice_to_str(slice)
  local string = ffi.string(slice.ptr, slice.len)
  crypter.crypter_free_slice(slice)
  return string
end

local function str_to_user(string)
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
    ngx.log(ngx.ALERT, "Expiry missing")
    return nil
  end

  local expiry = tonumber(fields[1])
  if not expiry then
    ngx.log(ngx.ALERT, "Maformed expiry")
    return nil
  end

  if os.time() - fields[1] > 172800 then
    ngx.log(ngx.ALERT, "Expired token")
    return nil
  end

  return {
    email = fields[2],
    given_name = fields[3],
    family_name = fields[4],
    picture = fields[5],
  }
end

local SECRET_SLICE = str_to_slice("$COOKIE_SECRET")

local function encrypt_user(user)
  local payload_slice = str_to_slice(string.format(
    "%d\0%s\0%s\0%s\0%s",
    os.time(),
    user.email,
    user.given_name,
    user.family_name,
    user.picture
  ))

  local encrypted = crypter.crypter_encrypt(SECRET_SLICE, payload_slice)
  if encrypted.ptr == nil then
    return nil
  end

  return ngx.encode_base64(slice_to_str(encrypted))
end

local function decrypt_user()
  local encoded = ngx.var.cookie_User

  if not encoded then
    encoded = ngx.req.get_headers()["X-USER-TOKEN"]
    if type(encoded) == 'table' then
      encoded = encoded[1]
    end
  end

  if not encoded or #encoded == 0 then
    return nil
  end

  local decoded = ngx.decode_base64(encoded)
  if not decoded then
    return nil
  end

  local decoded_slice = str_to_slice(decoded)
  local decrypted = crypter.crypter_decrypt(SECRET_SLICE, decoded_slice)

  if decrypted.ptr == nil then
    return nil
  end

  return str_to_user(slice_to_str(decrypted))
end

local function call_oidc(pass)
  local opts = {
    redirect_uri = "https://api.$HOST_NAME/callback",
    redirect_after_logout_uri = ngx.var.arg_redirect or ngx.req.get_headers()["Referer"],

    discovery = "https://accounts.google.com/.well-known/openid-configuration",

    client_id = "$CLIENT_ID",
    client_secret = "$CLIENT_SECRET",

    scope = "openid email profile",
    authorization_params = {
      login_hint = ngx.var.cookie_Email,
    },

    lifecycle = {
      on_logout = function()
        ngx.header["Set-Cookie"] = {
          "email=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax",
          "user=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax"
        }
      end,
    },
  }

  local res, err = require("resty.openidc").authenticate(opts, nil, pass)

  if err then
    ngx.status = 500
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  if not res then
    return nil
  end

  return res.user
end

local function auth(pass)
  local user_token = decrypt_user()

  local user = user_token or call_oidc(pass)

  if not (user and user.email) then
    ngx.status = 401
    if ngx.var.cookie_User then
      ngx.header["Set-Cookie"] = { "user=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax" }
    end
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return;
  end

  ngx.req.set_header("X-USER", user.email)
  if user.given_name then ngx.req.set_header("X-GIVEN-NAME", user.given_name) end
  if user.family_name then ngx.req.set_header("X-FAMILY-NAME", user.family_name) end
  if user.picture then ngx.req.set_header("X-PICTURE", user.picture) end

  local cookie

  if ngx.var.cookie_Session then
    cookie = { "session=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax" }
  end

  if not ngx.var.cookie_Email then
    if cookie then
      cookie = { unpack(cookie), "email=" .. user.email .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax" }
    else
      cookie = { "email=" .. user.email .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax" }
    end
  end

  local user_cookie = encrypt_user(user)
  if user_cookie then
    if cookie then
      cookie = { unpack(cookie), "user=" .. user_cookie .. ";Path=/;Max-Age=172800;Secure;HttpOnly;SameSite=lax" }
    else
      cookie = { "user=" .. user_cookie .. ";Path=/;Max-Age=172800;Secure;HttpOnly;SameSite=lax" }
    end
  end

  ngx.header["Set-Cookie"] = cookie

  local redirect = ngx.re.sub(ngx.var.request_uri, "^/(.*)", "/internal/$1", "o")
  if redirect then
    ngx.exec(redirect)
  else
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end
end

function auther.login()
  auth()
end

function auther.guard()
  auth("pass")
end

return auther
