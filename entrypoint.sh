#!/usr/bin/env bash

set -e

if [ ! -f "/etc/letsencrypt/live/$HOST_NAME/fullchain.pem" ]; then
  certbot \
    certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /opt/nginx/certbot/cloudflare.ini \
    --non-interactive \
    --agree-tos \
    --register-unsafely-without-email \
    -d "$HOST_NAME" \
    -d "*.$HOST_NAME"
fi

crond

exec /usr/local/openresty/bin/openresty -c /etc/nginx/nginx.conf -g "daemon off;"
