#!/usr/bin/env bash

function log {
  echo "[37m$(date '+[%Y-%m-%d %H:%M:%S]') ${1}[m"
}

log 'Starting certbot renewal script'

if [ ! -f /opt/nginx/certbot/cloudflare.ini ]; then
  log 'Token file was not found'
else
  certbot renew \
    --dns-cloudflare \
    --dns-cloudflare-credentials /opt/nginx/certbot/cloudflare.ini \
    --deploy-hook '/usr/local/openresty/bin/openresty -s reload'
fi
