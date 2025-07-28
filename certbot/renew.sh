#!/usr/bin/env bash

function log {
  echo "$(date '+[%Y-%m-%d %H:%M:%S]') ${1}"
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
