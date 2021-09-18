FROM openresty/openresty:alpine-fat

COPY index.html /usr/local/openresty/nginx/html/index.html
COPY conf /etc/nginx
COPY cert /var/cert
COPY oauth /var/oauth
COPY lua /etc/nginx/lua
COPY hostname.env /tmp/hostname.env

RUN apk add --no-cache nettle && \
    . /tmp/hostname.env && \
    sed -i "s~"'$HOST_NAME_REGEX'"~${HOST_NAME_REGEX}~" /etc/nginx/conf.d/*.conf && \
    sed -i "s~"'$HOST_NAME'"~${HOST_NAME}~" /etc/nginx/conf.d/*.conf && \
    mkdir /var/log/nginx && \
    . /var/oauth/oath.env && \
    envsubst '\$CLIENT_ID \$CLIENT_SECRET \$COOKIE_SECRET \$HOST_NAME' \
      < /etc/nginx/lua/auther.template.lua \
      > /etc/nginx/lua/auther.lua && \
    rm -rf /var/oauth && \
    rm /tmp/hostname.env && \
    rm /etc/nginx/lua/auther.template.lua && \
    luarocks install lua-resty-openidc && \
    luarocks install lua-resty-nettle

EXPOSE 80
EXPOSE 443

STOPSIGNAL SIGTERM

CMD ["/usr/local/openresty/bin/openresty", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]

