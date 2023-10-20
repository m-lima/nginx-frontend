# Required files:
# oauth/oauth.env:
#  - export CLIENT_ID=<oidc_id>
#  - export CLIENT_SECRET=<oidc_secret>
#  - export TOKEN_SECRET=<crypter_secret>
# hostname.env
#  - export HOST_NAME=<domain>
#  - export HOST_NAME_REGEX=<domain>\\\\<tld>
# certbot/cert:
#  - TLS pem files

FROM docker.io/openresty/openresty:1.21.4.2-1-alpine-fat

COPY index.html /usr/local/openresty/nginx/html/index.html
COPY conf /etc/nginx
COPY certbot/data/cert /var/cert
COPY oauth /var/oauth
COPY hostname.env /tmp/hostname.env

RUN mkdir /var/log/nginx && \
    mkdir /etc/nginx/lua && \
    . /tmp/hostname.env && \
    for conf in `find /etc/nginx -name '*.nginx' -type f`; do \
      sed -i "s~"'$HOST_NAME_REGEX'"~${HOST_NAME_REGEX}~" "$conf" && \
      sed -i "s~"'$HOST_NAME'"~${HOST_NAME}~" "$conf"; \
    done; \
    rm /tmp/hostname.env && \
    . /var/oauth/oauth.env && \
    [ "${CLIENT_ID}" ] && \
    [ "${CLIENT_SECRET}" ] && \
    [ "${TOKEN_SECRET}" ] && \
    envsubst '\$CLIENT_ID \$CLIENT_SECRET \$HOST_NAME' \
      < /var/oauth/lua/auther.template.lua \
      > /etc/nginx/lua/auther.lua && \
    envsubst '\$TOKEN_SECRET' \
      < /var/oauth/lua/crypter.template.lua \
      > /etc/nginx/lua/crypter.lua && \
    mv /var/oauth/lib/libcrypter.so /usr/local/lib/. && \
    rm -rf /var/oauth && \
    luarocks install lua-resty-openidc 1.7.6-3

EXPOSE 80
EXPOSE 443

STOPSIGNAL SIGTERM

CMD ["/usr/local/openresty/bin/openresty", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]
