#!/usr/bin/env bash

service_name="nginx"

function usage {
  local base=$(basename "${0}")
  echo "HELP"
  echo "  Builds and prepares a ${service_name} container"
  echo
  echo "USAGE"
  echo "  ${base} [OPTIONS]"
  echo "  ${base} unit [-d]"
  echo
  echo "COMMANDS"
  echo "  unit               Print a systemd unit file and quit"
  echo
  echo "OPTIONS"
  echo "  -v <name>:[<path>] Attach the given volume to <name>:/var/www/<name> or <path>:/var/www/<name>"
  echo "  -n <name>          Attach to the given network"
  echo "  -d                 Use docker instead of podman"
  echo "  -c                 Stop and start the service"
  echo "  -h                 Print this help message"
  echo
  echo "EXAMPLE"
  echo "  ${base} -v one: -c -v two:/tmp/www"
  echo "  ${base} unit -d > ${service_name}.service"
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
    ${pod} generate systemd --name "${service_name}" \
      | sed 's/^Description=.*$/Description=Nginx gateway into container network/g' \
      | sed 's/^Restart=.*$/Restart=always/g' \
      | sed 's/^WantedBy=.*$/WantedBy=multi-user.target/g'
  else
    bin=$(which "${pod}")

    cat <<EOF
[Unit]
Description=Nginx gateway into container network
After=${pod}.service
Requires=${pod}.service

[Service]
Restart=always
ExecStart=${bin} start -a ${service_name}
ExecStop=${bin} stop ${service_name}

[Install]
WantedBy=multi-user.target
EOF
  fi

  exit
}

function build {
  local base=$(dirname "${0}")
  base=$(realpath "${base}")
  local pod="podman"
  local cycle=""
  local output
  local volumes=""
  local autovolumes=$(
    for f in $(find -L conf/services/enabled -maxdepth 2 -type f -name server.nginx); do
      sed -rn 's~^[[:space:]]*root[[:space:]]+/var/www/(.+);[[:space:]]*$~\1~p' $f
    done
  )
  local volume_name
  local volume_path
  local networks=""

  while [ "${1}" ]; do
    case "${1}" in
      "-v")
        shift
        if [ "${1}" ]; then
          if [[ "${1}" =~ ^[^:/]+:(/.*)?$ ]]; then
            volume_name=$(cut -d':' -f1 <<<"${1}")
            volume_path=$(cut -d':' -f2 <<<"${1}")
            if [ "${volume_path}" ]; then
              if [ ! -d "${volume_path}" ]; then
                error "Volume path does not exist:" "${1}"
              fi
            else
              volume_path="${volume_name}"
            fi

            if ! grep "${volume_name}" <<<"${autovolumes}" &> /dev/null ; then
              echo "[33mAdding volume that is not detected as required:[m ${volume_name}"
            else
              autovolumes=$(sed "/${volume_name}/d" <<<"${autovolumes}")
            fi
            volumes="-v ${volume_path}:/var/www/${volume_name}:ro${volumes+ $volumes}"
          else
            error "Expected <name>:[<absolute_path>] for volume definition:" "${1}"
          fi
        else
          error "Expected a volume name for -v"
        fi
        ;;
      "-n")
        shift
        if [ "${1}" ]; then
          networks="${1}${networks+ $networks}"
        else
          error "Expected a network name for -n"
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
    systemctl stop "${service_name}"
  fi

  echo "[34mBuilding the image[m"
  if ! ${pod} build -t "${service_name}" "${base}"; then
    exit 1
  fi

  echo "[34mChecking for running instances[m"
  output=$(${pod} ps --format '{{.ID}} {{.Names}}' | grep "${service_name}")
  if [ "${output}" ]; then
    ${pod} stop $(cut -d' ' -f1 <<<"${output}")
  fi

  echo "[34mChecking for existing containers[m"
  output=$(${pod} ps -a --format '{{.ID}} {{.Names}}' | grep "${service_name}")
  if [ "${output}" ]; then
    ${pod} rm $(cut -d' ' -f1 <<<"${output}")
  fi

  echo "[34mChecking for existing network[m"
  output=$(${pod} network ls --format '{{.Name}}' | grep "${service_name}")
  if [ ! "${output}" ]; then
    ${pod} network create "${service_name}"
  fi

  echo "[34mCreating the container[m"
  ${pod} create \
    --publish 80:80 \
    --publish 443:443 \
    ${volumes} \
    --network "${service_name}" \
    --name "${service_name}" \
    "${service_name}"

  for net in ${networks[@]}; do
    echo "[34mConnecting to ${net}[m"
    ${pod} network connect "${net}" "${service_name}"
  done

  if [ ${cycle} ]; then
    echo "[34mStarting the service[m"
    systemctl start "${service_name}"
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

