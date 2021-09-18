local auther = {
  _VERSION = "0.0.1"
}

math.randomseed(os.time())

local function encrypt_user(user)
  local nonce = ""
  for i=1,12 do
    nonce = nonce .. string.char(math.floor(math.random() * 256))
  end

  local aes, err = require("resty.nettle.aes").new("$COOKIE_SECRET", "gcm", nonce)
  if err then
    ngx.log(ngx.ERR, err)
    return nil
  end

  local payload = string.format("%s\0%s\0%s\0%s", user.email, user.given_name, user.family_name, user.picture)

  local encrypted, digest = aes:encrypt(payload)
  if not encrypted then
    ngx.log(ngx.ERR, "Could not encrypt")
  end

  if encrypted then
    return ngx.encode_base64(encrypted .. digest .. nonce)
  else
    return nil
  end

end

local function decrypt_user()
  local encoded = ngx.var.cookie_User or ngx.req.get_headers()["X-USER-TOKEN"]
  if not encoded then
    return nil
  end

  local decoded, err = ngx.decode_base64(encoded)
  if err then
    return nil
  end

  local nonce = string.sub(decoded, -12)

  local aes, err = require("resty.nettle.aes").new("$COOKIE_SECRET", "gcm", nonce)
  if err then
    ngx.log(ngx.ERR, err)
    return nil
  end

  local expected_digest = string.sub(decoded, -28, -13)
  local decrypted, digest = aes:decrypt(string.sub(decoded, 0, -29))
  if not decrypted then
    return nil
  end

  if digest ~= expected_digest then
    return nil
  end

  local fields = {}
  local index = 1
  for i=1,#decrypted do
    if string.byte(decrypted, i) == 0 then
      table.insert(fields, string.sub(decrypted, index, i - 1))
      i = i + 1
      index = i
    end
  end
  table.insert(fields, string.sub(decrypted, index))

  return {
    email = fields[1],
    given_name = fields[2],
    family_name = fields[3],
    picture = fields[4],
  }
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

  local cookie = {}
  if not ngx.var.cookie_Email then
    cookie = { "email=" .. user.email .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax" }
  end

  if not user_token then
    local user_cookie = encrypt_user(user)
    if user then
      cookie = { unpack(cookie), "user=" .. user_cookie .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax" }
    end
  end

  ngx.header["Set-Cookie"] = cookie

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
