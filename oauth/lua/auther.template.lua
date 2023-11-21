ngx.log(ngx.STDERR, 'Loading auther')

local openidc = require('resty.openidc')
local crypter = require('crypter')

local token_ttl = 345600
local token_cookie_suffix = ';Path=/;Max-Age=' .. token_ttl .. ';Secure;HttpOnly;SameSite=lax'

local function call_oidc(pass)
  local opts = {
    redirect_uri = 'https://api.$HOST_NAME/callback',
    redirect_after_logout_uri = ngx.var.arg_redirect or ngx.req.get_headers()['Referer'],

    discovery = 'https://accounts.google.com/.well-known/openid-configuration',

    client_id = '$CLIENT_ID',
    client_secret = '$CLIENT_SECRET',

    scope = 'openid email profile',
    authorization_params = {
      login_hint = ngx.var.cookie_email,
    },

    lifecycle = {
      on_logout = function()
        ngx.header.set_cookie = {
          'email=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax',
          'user=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax'
        }
      end,
    },
  }

  local res, err = openidc.authenticate(opts, nil, pass)

  if err then
    ngx.status = 500
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
    return nil
  end

  if not res then
    return nil
  end

  return res.user
end

local function get_user(pass)
  -- Try token from headers first
  local encoded = ngx.var.http_x_user_token
  if type(encoded) == 'table' then
    encoded = encoded[1]
  end

  -- Then try token from cookies
  if not encoded then
    encoded = ngx.var.cookie_user
  end

  -- Try parsing the token
  local user = crypter.decrypt_user(encoded, token_ttl)

  -- Fallback to OIDC if it fails
  return user or call_oidc(pass)
end

local function set_user(user)
  ngx.req.set_header('X-USER', user.email)
  if user.given_name then ngx.req.set_header('X-GIVEN-NAME', user.given_name) end
  if user.family_name then ngx.req.set_header('X-FAMILY-NAME', user.family_name) end
  if user.picture then ngx.req.set_header('X-PICTURE', user.picture) end

  -- Only update the token if enough time has passed
  if user.age and ngx.time() - user.age > token_ttl / 2 then
    local cookie = {}

    -- Remove session cookie, if present
    if ngx.var.cookie_session then
      cookie = { 'session=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax' }
    end

    -- Add email hint, if missing
    if not ngx.var.cookie_email then
      table.insert(cookie, 'email=' .. user.email .. ';Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax')
    end

    -- Add user token, if possible
    local user_token = crypter.encrypt_user(user)
    if user_token then
      table.insert(cookie, 'user=' .. user_token .. token_cookie_suffix)
    end

    ngx.header.set_cookie = cookie
  end
end

local function auth(pass)
  local user = get_user(pass)

  if not (user and user.email) then
    ngx.status = 401
    if ngx.var.cookie_user then
      ngx.header.set_cookie = { 'user=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax' }
    end
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return;
  end

  set_user(user)

  local redirect = ngx.re.sub(ngx.var.request_uri, '^/(.*)', '/internal/$1', 'o')
  if redirect then
    ngx.exec(redirect)
  else
    ngx.exit(ngx.HTTP_BAD_REQUEST)
  end
end

local M = {
  _VERSION = '0.0.1',

  login = function() auth() end,
  guard = function() auth('pass') end,
}

return M
