local auther = {
  _VERSION = "0.0.1"
}

ffi = require('ffi')

ffi.cdef[[
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
]]

crypter = ffi.load("crypter")

local function str_to_slice(text)
  local slice = ffi.new("CrypterCSlice")

  ptr = ffi.new('uint8_t[?]', #text)
  ffi.copy(ptr, text)

  slice.ptr = ffi.cast("uint8_t *", ptr)
  slice.len = #text
  return slice, ptr
end

local function slice_to_str(slice)
  local string = ffi.string(slice.ptr, slice.len)
  crypter.crypter_free_slice(slice)
  return string
end

local function str_to_user(string)
  local fields = {}
  local index = 1
  for i=1,#string do
    if string.byte(string, i) == 0 then
      table.insert(fields, string.sub(string, index, i - 1))
      i = i + 1
      index = i
    end
  end
  table.insert(fields, string.sub(string, index))

  return {
    email = fields[1],
    given_name = fields[2],
    family_name = fields[3],
    picture = fields[4],
  }
end

SECRET_SLICE, SECRET_PTR = str_to_slice("$COOKIE_SECRET")

local function encrypt_user(user)
  local payload_slice, payload_ptr = str_to_slice(string.format("%s\0%s\0%s\0%s", user.email, user.given_name, user.family_name, user.picture))

  local encrypted = crypter.crypter_encrypt(SECRET_SLICE, payload_slice)
  if encrypted.ptr == nil then
    return nil
  end

  return ngx.encode_base64(slice_to_str(encrypted))
end

local function decrypt_user()
  local encoded = ngx.var.cookie_User or ngx.req.get_headers()["X-USER-TOKEN"]
  if not encoded then
    return nil
  end

  local decoded = ngx.decode_base64(encoded)
  if not decoded then
    return nil
  end

  local decoded_slice, decoded_ptr = str_to_slice(decoded)
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
      on_logout = function(session)
        ngx.header["Set-Cookie"] = { "email=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax", "user=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax" }
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
    ngx.header["Set-Cookie"] = { "email=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax", "user=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax" }
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
  end

  ngx.req.set_header("X-USER", user.email)
  ngx.req.set_header("X-GIVEN-NAME", user.given_name)
  ngx.req.set_header("X-FAMILY-NAME", user.family_name)
  ngx.req.set_header("X-PICTURE", user.picture)

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

  if not user_token then
    local user_cookie = encrypt_user(user)
    if user_cookie then
      if cookie then
        cookie = { unpack(cookie), "user=" .. user_cookie .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax" }
      else
        cookie = { "user=" .. user_cookie .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax" }
      end
    end
  end

  if cookie then
    ngx.header["Set-Cookie"] = cookie
  end

  local redirect = ngx.re.sub(ngx.var.request_uri, "^/(.*)", "/internal/$1", "o")
  ngx.exec(redirect)
end

function auther.login()
  auth()
end

function auther.guard()
  auth("pass")
end

return auther
