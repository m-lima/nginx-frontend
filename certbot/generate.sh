#!/usr/bin/env bash

function usage {
  local base=`basename "${0}"`
  echo "HELP"
  echo "  ${base} will generate letsencrypt certificates using godaddy DNS challenge"
  echo "  Godaddy keys are expected to be in var/godaddy_credentials.ini"
  echo "  Generated certificates will be in etc/archive/<domain>/"
  echo
  echo "USAGE"
  echo "  ${base} <domain> [OPTIONS]"
  echo
  echo "OPTIONS"
  echo "  -w            Generate wildcard certificate"
  echo "  -d            Use docker instead of podman"
  echo "  -t <seconds>  Godaddy DNS propagation timeout in seconds"
  echo "  -h            Print this help message"
  echo
  echo "EXAMPLE"
  echo "  ${base} example.com -w -t 90"
  echo
  echo "GODADDY CREDENTIALS FORMAT"
  echo "   dns_godaddy_secret=<SECRET>"
  echo "   dns_godaddy_key=<KEY>"
}

function error {
  echo -n "[31m${1}[m" >&2
  if [ "${2}" ]; then
    echo " ${2}" >&2
  else
    echo >&2
  fi

  echo >&2
  usage >&2
  exit 1
}

base=`dirname "${0}"`

for p in ${@}; do
  if [[ "${p}" == "-h" ]]; then
    usage
    exit
  fi
done

if [ ! "${1}" ]; then
  error "Expected a domain parameter"
fi

domain="${1}"
wildcard=""
timeout="60"
pod="podman"

shift
while [ "${1}" ]; do
  case "${1}" in
    "-w") wildcard='*.'"${domain}" ;;
    "-d") pod="docker" ;;
    "-t")
      shift
      if [ "${1}" ] && [[ "${1}" =~ ^[0-9]+$ ]]; then
        timeout="${1}"
      else
        error "Expected a timeout in seconds for -t"
      fi
      ;;
    *) error "Unknown parameter:" "${1}" ;;
  esac
  shift
done

if [ ! -f "${base}/var/godaddy_credentials.ini" ]; then
  error "Missing godaddy credentials file at" "${base}/var/godaddy_credentials.ini"
fi

[ -d "${base}/../cert" ] || mkdir "${base}/../cert"
[ -d "${base}/etc" ] || mkdir "${base}/etc"

echo -n "Generating certificates in ${base}/etc/archive/${domain}/ for '${domain}'"
if [ "${wildcard}" ]; then
  echo -n " and '${wildcard}'"
fi
echo " with a ${timeout}s timeout"

if [ "${wildcard}" ]; then
  domain="-d ${wildcard} -d ${domain}"
else
  domain="-d ${domain}"
fi

${pod} run --rm \
  --name certbot-godaddy \
  -v ${base}/etc:/etc/letsencrypt \
  -v ${base}/var:/var/lib/letsencrypt \
  --cap-drop=all \
  docker.io/miigotu/certbot-dns-godaddy \
    certbot certonly \
    --authenticator dns-godaddy \
    --dns-godaddy-propagation-seconds "${timeout}" \
    --dns-godaddy-credentials /var/lib/letsencrypt/godaddy_credentials.ini \
    --keep-until-expiring \
    --non-interactive \
    --expand \
    --server https://acme-v02.api.letsencrypt.org/directory \
    --agree-tos \
    --register-unsafely-without-email \
    ${domain} \
&& cp "${base}/etc/live/${domain}/"* "${base}/../cert/."

# ${pod} run -it --rm --name certbot \
#   -v ${base}/etc:/etc/letsencrypt \
#   -v ${base}/var:/var/lib/letsencrypt \
#   docker.io/certbot/certbot \
#   certonly --manual ${domain} \
#   --preferred-challenges dns \
#   --server https://acme-v02.api.letsencrypt.org/directory \
#   --register-unsafely-without-email \
#   --agree-tos --manual-public-ip-logging-ok
