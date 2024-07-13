#!/usr/bin/env bash

function usage {
  local base=`basename "${0}"`
  echo "HELP"
  echo "  ${base} will generate letsencrypt certificates using DNS challenge"
  echo "  It is expected that the TXT entries for the domain can be updated"
  echo "  Generated certificates will be in data/etc/archive/<domain>/"
  echo
  echo "USAGE"
  echo "  ${base} <domain> [OPTIONS]"
  echo
  echo "OPTIONS"
  echo "  -w            Generate wildcard certificate"
  echo "  -d            Use docker instead of podman"
  echo "  -h            Print this help message"
  echo
  echo "EXAMPLE"
  echo "  ${base} example.com -w"
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
pod="podman"

shift
while [ "${1}" ]; do
  case "${1}" in
    "-w") wildcard='*.'"${domain}" ;;
    "-d") pod="docker" ;;
    *) error "Unknown parameter:" "${1}" ;;
  esac
  shift
done

[ -d "${base}/data" ] || mkdir "${base}/data"
[ -d "${base}/data/cert" ] || mkdir "${base}/data/cert"
[ -d "${base}/data/etc" ] || mkdir "${base}/data/etc"

if [ "${wildcard}" ]; then
  domain_param="-d ${wildcard} -d ${domain}"
else
  domain_param="-d ${domain}"
fi

${pod} run --rm -it \
  --name certbot \
  -v ${base}/data/etc:/etc/letsencrypt \
  -v ${base}/data/var:/var/lib/letsencrypt \
  docker.io/certbot/certbot \
  certonly --manual \
  --preferred-challenges dns \
  --server https://acme-v02.api.letsencrypt.org/directory \
  --register-unsafely-without-email \
  --agree-tos \
  --manual-public-ip-logging-ok \
  ${domain_param} \
&& cp "${base}/data/etc/live/${domain}/"* "${base}/data/cert/."
