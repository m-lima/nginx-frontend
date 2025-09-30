# Required files:
#   oauth/oauth.env:
#    - export CLIENT_ID=<oidc_id>
#    - export CLIENT_SECRET=<oidc_secret>
#    - export TOKEN_SECRET=<crypter_secret>
#   hostname.env
#    - export HOST_NAME=<domain>
#    - export HOST_NAME_REGEX=<domain>\\\\<tld>
#   certbot/token: DNS API token
#   certbot/renew.sh: Script to renew the DNS
#   certbot/reload.sh: Script to reload nginx upon renewal
#   entrypoint.sh: Entrypoint script
#
# Required volumes:
#   certbot-etc

FROM docker.io/openresty/openresty:1.25.3.2-5-alpine-fat

COPY entrypoint.sh /tmp/entrypoint.sh
COPY index.html /usr/local/openresty/nginx/html/index.html
COPY conf /etc/nginx
COPY certbot/renew.sh /opt/nginx/certbot/renew.sh
COPY certbot/reload.sh /opt/nginx/certbot/reload.sh
COPY certbot/token/cloudflare.ini /opt/nginx/certbot/cloudflare.ini
COPY oauth /tmp/oauth
COPY hostname.env /tmp/hostname.env

RUN apk add --no-cache certbot certbot-dns-cloudflare busybox-suid && \
    mkdir /etc/nginx/lua && \
    . /tmp/hostname.env && \
    for conf in $(find /etc/nginx -name '*.nginx' -type f; echo /etc/nginx/nginx.conf); do \
      sed -i "s~"'$HOST_NAME_REGEX'"~${HOST_NAME_REGEX}~g" "$conf" && \
      sed -i "s~"'$HOST_NAME'"~${HOST_NAME}~g" "$conf"; \
    done; \
    envsubst '\$HOST_NAME' \
      < /tmp/entrypoint.sh \
      > /opt/nginx/entrypoint.sh && \
    rm /tmp/entrypoint.sh && \
    rm /tmp/hostname.env && \
    . /tmp/oauth/oauth.env && \
    [ "${CLIENT_ID}" ] && \
    [ "${CLIENT_SECRET}" ] && \
    [ "${TOKEN_SECRET}" ] && \
    envsubst '\$CLIENT_ID \$CLIENT_SECRET \$HOST_NAME' \
      < /tmp/oauth/lua/auther.template.lua \
      > /etc/nginx/lua/auther.lua && \
    envsubst '\$TOKEN_SECRET' \
      < /tmp/oauth/lua/crypter.template.lua \
      > /etc/nginx/lua/crypter.lua && \
    mv /tmp/oauth/lib/libcrypter.so /usr/local/lib/. && \
    rm -rf /tmp/oauth && \
    luarocks install lua-resty-openidc 1.7.6-3 && \
    chmod 600 /opt/nginx/certbot/cloudflare.ini && \
    chmod +x /opt/nginx/entrypoint.sh && \
    chmod +x /opt/nginx/certbot/renew.sh && \
    chmod +x /opt/nginx/certbot/reload.sh && \
    echo '0 6 * * * /opt/nginx/certbot/renew.sh >> /var/log/certbot.log 2>&1' > /etc/crontabs/root

EXPOSE 80
EXPOSE 443

STOPSIGNAL SIGQUIT

CMD [ "/opt/nginx/entrypoint.sh" ]
