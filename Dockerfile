FROM docker.io/openresty/openresty:1.21.4.2-1-alpine-fat

COPY index.html /usr/local/openresty/nginx/html/index.html
COPY conf /etc/nginx
COPY cert /var/cert
COPY oauth /var/oauth
COPY lua /etc/nginx/lua
COPY hostname.env /tmp/hostname.env
# COPY --from=crypter /src/target/release/libcrypter.so /usr/local/lib/.
COPY lib/libcrypter.so /usr/local/lib/.

RUN . /tmp/hostname.env && \
    for conf in `find /etc/nginx -name '*.nginx' -type f`; do \
      sed -i "s~"'$HOST_NAME_REGEX'"~${HOST_NAME_REGEX}~" "$conf" && \
      sed -i "s~"'$HOST_NAME'"~${HOST_NAME}~" "$conf"; \
    done; \
    mkdir /var/log/nginx && \
    . /var/oauth/oauth.env && \
    envsubst '\$CLIENT_ID \$CLIENT_SECRET \$HOST_NAME' \
      < /etc/nginx/lua/auther.template.lua \
      > /etc/nginx/lua/auther.lua && \
    envsubst '\$TOKEN_SECRET' \
      < /etc/nginx/lua/crypter.template.lua \
      > /etc/nginx/lua/crypter.lua && \
    rm -rf /var/oauth && \
    rm /tmp/hostname.env && \
    rm /etc/nginx/lua/auther.template.lua && \
    rm /etc/nginx/lua/crypter.template.lua && \
    luarocks install lua-resty-openidc

EXPOSE 80
EXPOSE 443

STOPSIGNAL SIGTERM

CMD ["/usr/local/openresty/bin/openresty", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]

