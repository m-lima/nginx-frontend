#!/usr/bin/env bash

function usage {
  local base=`basename "${0}"`
  echo "HELP"
  echo "  Builds and prepares a nginx-frontend container"
  echo
  echo "USAGE"
  echo "  ${base} [OPTIONS]"
  echo "  ${base} unit [-d]"
  echo
  echo "COMMANDS"
  echo "  unit        Print a systemd unit file and quit"
  echo
  echo "OPTIONS"
  echo "  -v <volume> Attach the given volume to /var/www/<volume>"
  echo "  -d          Use docker instead of podman"
  echo "  -c          Stop and start the service"
  echo "  -h          Print this help message"
  echo
  echo "EXAMPLE"
  echo "  ${base} -v one -c -v two"
  echo "  ${base} unit -d > nginx-frontend.service"
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

function unit {
  bin=`which "${1}"`
  cat <<EOF
[Unit]
Description=Web Gateway for ${HOST}
After=${1}.service
Requires=${1}.service

[Service]
Restart=always
ExecStart=${bin} start -a nginx-frontend
ExecStop=${bin} stop nginx-frontend

[Install]
WantedBy=multi-user.target
EOF
}

for p in ${@}; do
  if [[ "${p}" == "-h" ]]; then
    usage
    exit
  fi
done

if [[ "${1}" == "unit" ]]; then
  pod="podman"

  shift
  if [ "${1}" ]; then
    if [[ "${1}" == "-d" ]]; then
      pod="docker"
    else
      error "Unknown parameter:" "${1}"
    fi
  fi

  if ! command -v ${pod} > /dev/null; then
    error "Not found:" "${pod}"
  fi

  unit ${pod}
  exit
fi

cd "`dirname "${0}"`"

volumes=""
cycle=""

while [ "${1}" ]; do
  case "${1}" in
    "-v")
      shift
      if [ "${1}" ]; then
        if [[ "${1}" =~ ^[^/]+$ ]]; then
          volumes="-v ${1}:/var/www/${1}:ro${volumes+ $volumes}"
        else
          error "Invalid volume name:" "${1}"
        fi
      else
        error "Expected a volume name for -v"
      fi
      ;;
    "-d") pod="docker" ;;
    "-c") cycle="1" ;;
    *) error "Unknown parameter:" "${1}" ;;
  esac
  shift
done

if [ ${cycle} ]; then
  systemctl stop nginx-frontend
fi

echo "[34mBuilding the image[m"
if ! ${pod} build -t nginx-frontend .; then
  exit 1
fi

echo "[34mChecking for running instances[m"
output=`${pod} ps --format '{{.ID}} {{.Names}}' | grep nginx-frontend`
if [ "${output}" ]; then
  ${pod} stop `cut -d' ' -f1 <<<"${output}"`
fi

echo "[34mChecking for existing containers[m"
output=`${pod} ps -a --format '{{.ID}} {{.Names}}' | grep nginx-frontend`
if [ "${output}" ]; then
  ${pod} rm `cut -d' ' -f1 <<<"${output}"`
fi

echo "[34mChecking for existing network[m"
output=`${pod} network ls --format '{{.Names}}' | grep nginx`
if [ ! "${output}" ]; then
  ${pod} network create nginx
fi

echo "[34mCreating the container[m"
${pod} create \
  --publish 80:80 \
  --publish 443:443 \
  --volume /var/www/html/public:/var/www/static:ro \
  ${volumes} \
  --net nginx \
  --name nginx-frontend \
  nginx-frontend

if [ ${cycle} ]; then
  systemctl start nginx-frontend
fi
