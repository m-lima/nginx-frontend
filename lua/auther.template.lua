local auther = {
  _VERSION = "0.0.1"
}

local function auth(pass)
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

    Lifecycle is still not supported on stable
    lifecycle = {
      on_authenticated = function(session)
        ngx.log(ngx.ERROR, "login: " .. session.user.email)
        ngx.header["Set-Cookie"] = "email=" .. session.user.email .. ";Path=/;Max-Age=2592000;Secure;HttpOnly;SameSite=lax"
      end,

      on_logout = function(session)
        ngx.log(ngx.ERROR, "logout: " .. session.user.email)
        ngx.header["Set-Cookie"] = "email=;Path=/;Max-Age=0;Secure;HttpOnly;SameSite=lax"
      end,
    },
  }

  local res, err = require("resty.openidc").authenticate(opts, nil, pass)

  if err then
    ngx.status = 500
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end

  if not (res and res.user and res.user.email) then
    ngx.status = 401
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
  end

  ngx.req.set_header("X-USER", res.user.email)
  ngx.req.set_header("X-GIVEN-NAME", res.user.given_name)
  ngx.req.set_header("X-FAMILY-NAME", res.user.family_name)
  ngx.req.set_header("X-PICTURE", res.user.picture)

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
