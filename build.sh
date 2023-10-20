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
  echo "  -s <path>   Path to serve public static files from (defaults to www/public)"
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
  local pod bin
  pod="podman"

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

  if [[ "${pod}" == "podman" ]]; then
    ${pod} generate systemd --name nginx-frontend | sed 's/^Description=.*$/Description=Nginx gateway into container network/g'
  else
    bin=`which "${pod}"`

    cat <<EOF
[Unit]
Description=Nginx gateway into container network
After=${pod}.service
Requires=${pod}.service

[Service]
Restart=always
ExecStart=${bin} start -a nginx-frontend
ExecStop=${bin} stop nginx-frontend

[Install]
WantedBy=multi-user.target
EOF
  fi

  exit
}

function build {
  local base=`dirname "${0}"`
  base=`realpath "${base}"`
  local pod="podman"
  local static=""
  local volumes=""
  local cycle=""
  local output
  local autovolumes=`for f in conf/services/enabled/*/server.nginx; do sed -rn 's~^[[:space:]]*root[[:space:]]+/var/www/(.+);[[:space:]]*$~\1~p' $f; done`

  while [ "${1}" ]; do
    case "${1}" in
      "-v")
        shift
        if [ "${1}" ]; then
          if [[ "${1}" =~ ^[^/]+$ ]]; then
            if ! grep "${1}" <<<"${autovolumes}" &> /dev/null ; then
              echo "[33mAdding volume that is not detected as required:[m ${1}"
            else
              autovolumes=`sed "/${1}/d" <<<"${autovolumes}"`
            fi
            volumes="-v ${1}:/var/www/${1}:ro${volumes+ $volumes}"
          else
            error "Invalid volume name:" "${1}"
          fi
        else
          error "Expected a volume name for -v"
        fi
        ;;
      "-s")
        if [ "${static}" ]; then
          error "Static hosting path specified multiple times"
        fi
        shift
        if [ "${1}" ]; then
          if [ -d "${1}" ]; then
            static=`realpath "${1}"`
          else
            error "Path for static hosting does not exist:" "${1}"
          fi
        else
          error "Expected a path for -s"
        fi
        ;;
      "-d") pod="docker" ;;
      "-c") cycle="1" ;;
      *) error "Unknown parameter:" "${1}" ;;
    esac
    shift
  done

  if [ "${autovolumes}" ]; then
    echo "[33mNot all volumes detected as required were added:[m"
    echo "${autovolumes}"
  fi

  if [ ${cycle} ]; then
    echo "[34mStopping the service[m"
    systemctl stop nginx-frontend
  fi

  echo "[34mBuilding the image[m"
  if ! ${pod} build -t nginx-frontend "${base}"; then
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
  output=`${pod} network ls --format '{{.Name}}' | grep nginx`
  if [ ! "${output}" ]; then
    ${pod} network create nginx
  fi

  if [ ! "${static}" ]; then
    static="${base}/www/public"
    if [ ! -d "${static}" ]; then
      echo "[34mCreating default static serving point at[m ${static}"
      mkdir -p "${static}"
    fi
  fi

  echo "[34mCreating the container[m"
  ${pod} create \
    --publish 80:80 \
    --publish 443:443 \
    --volume "${static}":/var/www/static:ro \
    ${volumes} \
    --network nginx \
    --network host \
    --name nginx-frontend \
    nginx-frontend

  if [ ${cycle} ]; then
    echo "[34mStarting the service[m"
    systemctl start nginx-frontend
  fi
}

for p in ${@}; do
  if [[ "${p}" == "-h" ]]; then
    usage
    exit
  fi
done

if [[ "${1}" == "unit" ]]; then
  shift
  unit ${@}
else
  build ${@}
fi

