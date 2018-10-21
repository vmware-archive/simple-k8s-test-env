#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the kube-update service to monitor a vSphere GuestInfo property
# and update one or more Kubernetes components when the property value changes.
#
# The monitored property is "guestinfo.kube-update.url". Valid URLs must
# adhere to the pattern '^\(\(https\{0,1\}\)\|file\)://'. In other words
# the following URL schemes are supported: http, https, and file.
#
# Please note that all URLs using the "file://" scheme must use absolute paths.
#

set -e
set -o pipefail

# echo2 echoes the provided arguments to file descriptor 2, stderr.
echo2() { echo "${@}" 1>&2; }

# error is an alias for echo2
error() { echo2 "${@}"; }

# fatal echoes a string to stderr and then exits the program.
fatal() { exit_code="${2:-${?}}"; echo2 "${1}"; exit "${exit_code}"; }

# If the rpctool command cannot be found and RPCTOOL is set,
# then update the PATH to include the RPCTOOL's parent directory.
if ! command -v rpctool >/dev/null 2>&1 && [ -f "${RPCTOOL}" ]; then
  PATH="$(dirname "${RPCTOOL}"):${PATH}"; export PATH
fi

# If the rpctool command cannot be found then abort the script.
if ! command -v rpctool >/dev/null 2>&1; then
  fatal "failed to find rpctool command"
fi

# The GuestInfo property to monitor for update information.
RPC_KEY_URL="kube-update.url"

# The GuestInfo property to communicate the status to the client.
RPC_KEY_STATUS="kube-update.status"

# The GuestInfo property that lets clients monitor an update process.
RPC_KEY_LOG="kube-update.log"

# The file to which update messages are written.
UPDATE_LOG="$(mktemp)" || fatal "failed to create UPDATE_LOG"

# The temp directory where files are downloaded before being relocated
# to their permanent location.
TEMP_FILE_AREA="$(mktemp -d)" || fatal "failed to create TEMP_FILE_AREA"

# The temp file used to contain the names of the files in TEMP_FILE_AREA.
TEMP_FILE_LIST="$(mktemp)" || fatal "failed to create TEMP_FILE_LIST"

# The default directory to which to copy updated binaries.
BIN_DIR="${BIN_DIR:-/opt/bin}"

# The following environment variables are the locations of the eponymous
# Kubernetes binaries.
KUBECTL_BIN="${KUBECTL_BIN:-${BIN_DIR}/kubectl}"
KUBELET_BIN="${KUBELET_BIN:-${BIN_DIR}/kubelet}"
KUBE_APISERVER_BIN="${KUBE_APISERVER_BIN:-${BIN_DIR}/kube-apiserver}"
KUBE_CONTROLLER_MANAGER_BIN="${KUBE_CONTROLLER_MANAGER_BIN:-${BIN_DIR}/kube-controller-manager}"
KUBE_SCHEDULER_BIN="${KUBE_SCHEDULER_BIN:-${BIN_DIR}/kube-scheduler}"
KUBE_PROXY_BIN="${KUBE_PROXY_BIN:-${BIN_DIR}/kube-proxy}"

mkdir -p "$(dirname "${KUBECTL_BIN}")"
mkdir -p "$(dirname "${KUBELET_BIN}")"
mkdir -p "$(dirname "${KUBE_APISERVER_BIN}")"
mkdir -p "$(dirname "${KUBE_CONTROLLER_MANAGER_BIN}")"
mkdir -p "$(dirname "${KUBE_SCHEDULER_BIN}")"
mkdir -p "$(dirname "${KUBE_PROXY_BIN}")"

# The default curl command to use instead of invoking curl directly.
CURL="curl --retry 5 --retry-delay 1 --retry-max-time 120"

# Print the configuration properties
print_config_val() {
  printf '  %-30s= %s\n' "${1}" "$(eval echo "\$${1}")"
}
echo "kube-update config:"
print_config_val PATH
print_config_val CURL
print_config_val RPC_KEY_URL
print_config_val RPC_KEY_STATUS
print_config_val RPC_KEY_LOG
print_config_val UPDATE_LOG
print_config_val TEMP_FILE_AREA
print_config_val TEMP_FILE_LIST
print_config_val BIN_DIR
print_config_val KUBECTL_BIN
print_config_val KUBELET_BIN
print_config_val KUBE_APISERVER_BIN
print_config_val KUBE_CONTROLLER_MANAGER_BIN
print_config_val KUBE_SCHEDULER_BIN
print_config_val KUBE_PROXY_BIN
echo

rpc_set() {
  rpctool set "${1}" "${2}" || fatal "rpctool: set ${1}=${2} failed"
}
rpc_set_url() {
  rpc_set "${RPC_KEY_URL}" "${1}"
}
rpc_set_status() {
  rpc_set "${RPC_KEY_STATUS}" "${1}"
}
rpc_flush_log() {
  rpc_set "${RPC_KEY_LOG}" - <"${UPDATE_LOG}"
}
rpc_reset_log() {
  printf '' >"${UPDATE_LOG}"
  rpc_flush_log
}
rpc_log() {
  echo "${@}" >>"${UPDATE_LOG}"
  rpc_flush_log
}
rpc_info() {
  echo "${@}"
  rpc_log "${@}"
}
rpc_error() {
  error "error: ${1}"
  rpc_log "error: ${1}"
  rpc_set_status error
}
rpc_fatal() {
  exit_code="${?}"
  error "fatal: ${1}"
  rpc_log "fatal: ${1}"
  rpc_set_status fatal
  exit "${exit_code}"
}
rpc_exec() {
  rpc_log "${@}"
  "${@}" 2>&1 | tee -a "${UPDATE_LOG}"
  exit_code="${?}"
  rpc_flush_log
  return "${exit_code}"
}

echo "beginning message loop..."

while true; do
  sleep 1

  # Indicate to clients that the service is ready to recieve a new URL.
  rpc_set_status ready

  # Reset the TEMP_FILE_AREA and TEMP_FILE_LIST
  rm -fr "${TEMP_FILE_AREA}" "${TEMP_FILE_LIST}"
  mkdir -p "${TEMP_FILE_AREA}"

  # If the rpctool command fails then exit the script.
  if ! url=$(rpctool get "${RPC_KEY_URL}"); then
    rpc_fatal "rpctool: get '${RPC_KEY_URL}' failed"
  fi

  # If the URL is undefined or "null" then just continue to the next loop.
  { [ ! -z "${url}" ] && [ ! "${url}" = "null" ]; } || continue

  # Update the status to that of the URL value.
  rpc_set_status "${url}"

  # Rest the update log.
  rpc_reset_log

  # Set the update URL to "null" since the rpctool cannot delete a guestinfo
  # value. It's not even clear if the RPC interface can do it. Setting the
  # URL to "null" indicates to this script that the previous URL has been
  # removed but no new one has been set.
  rpc_set_url "null"

  # If the URL does not begin with "http://", "https://", or "file://" then
  # continue to the next iteration of the loop.
  if ! echo "${url}" | grep -iq '^\(\(https\{0,1\}\)\|file\)://'; then
    rpc_error "invalid-url: ${url}"
    continue
  fi

  # Indicate the URL is being processed.
  rpc_info "processing URL = ${url}"

  # Get the file name from the URL.
  if ! file_name="$(basename "${url}")"; then
    rpc_error "failed to get base name of URL=${url}"
    continue
  fi

  if echo "${file_name}" | grep -q '\.tar\.gz$'; then
    if ! ${CURL} -L "${url}" | tar -xzC "${TEMP_FILE_AREA}"; then
      rpc_error "failed to download and inflate ${url}"
      continue
    fi
  elif echo "${file_name}" | grep -q '\.tar$'; then
    if ! ${CURL} -L "${url}" | tar -xC "${TEMP_FILE_AREA}"; then
      rpc_error "failed to download and inflate ${url}"
      continue
    fi
  elif echo "${file_name}" | grep -q '\.gz$'; then
    if ! ${CURL} -Lo "${TEMP_FILE_AREA}/${file_name}"; then
      rpc_error "failed to download ${url}"
      continue
    fi
    if ! (cd "${TEMP_FILE_AREA}" && \
          gzip -d "${TEMP_FILE_AREA}/${file_name}"); then
      rpc_error "failed to inflate ${TEMP_FILE_AREA}/${file_name}"
      continue
    fi
    rm -f "${TEMP_FILE_AREA}/${file_name}"
  elif ! ${CURL} -Lo "${TEMP_FILE_AREA}/${file_name}" "${url}"; then
    rpc_error "failed to download ${url}"
    continue
  fi

  # Find all the files in TEMP_FILE_AREA.
  if ! find "${TEMP_FILE_AREA}" -type f 1>"${TEMP_FILE_LIST}"; then
    rpc_fatal "failed to find files in TEMP_FILE_AREA"
  fi

  # Iterate over the discovered files.
  while IFS= read -r file_path; do

    # If the file path does not exist then skip it.
    [ -f "${file_path}" ] || continue

    # Get the file's basename (no directory) or skip to the next iteration.
    file_name="$(basename "${file_path}")" || \
      { rpc_error "skipping '${file_path}'; basename failed"; continue; }

    # The action taken on each file depends on the file's name.
    src_bin="${file_path}"
    case "${file_name}" in
    kubectl)
      unset service_name
      tgt_bin="${KUBECTL_BIN}"
      ;;
    kubelet)
      service_name="${file_name}"
      tgt_bin="${KUBELET_BIN}"
      ;;
    kube-apiserver)
      service_name="${file_name}"
      tgt_bin="${KUBE_APISERVER_BIN}"
      ;;
    kube-controller-manager)
      service_name="${file_name}"
      tgt_bin="${KUBE_CONTROLLER_MANAGER_BIN}"
      ;;
    kube-scheduler)
      service_name="${file_name}"
      tgt_bin="${KUBE_SCHEDULER_BIN}"
      ;;
    kube-proxy)
      service_name="${file_name}"
      tgt_bin="${KUBE_PROXY_BIN}"
      ;;
    *)
      unset service_name
      unset tgt_bin
      ;;
    esac

    # If no target path was set then skip the rest of this iteration.
    if [ -z "${tgt_bin}" ]; then
      error "skipping unknown file '${file_path}'"
      continue
    fi

    printf 'updating %s:\n  %-10s= %s\n  %-10s= %s\n  %-10s= %s\n' \
      "${file_name}" \
      src_bin "${src_bin}" \
      tgt_bin "${tgt_bin}" \
      service "${service_name}" | tee -a "${UPDATE_LOG}"
    rpc_flush_log

    rpc_exec chmod 0755 "${src_bin}" || \
      { rpc_error "failed to chmod 0755 ${src_bin}"; continue; }

    if [ -z "${service_name}" ]; then
      rpc_exec mv -f "${src_bin}" "${tgt_bin}" || \
        { rpc_error "failed to mv '${src_bin}' to '${tgt_bin}'"; continue; }
    else
      rpc_exec systemctl -l stop "${service_name}" || \
        { rpc_error "failed to stop ${service_name}"; continue; }

      rpc_exec mv -f "${src_bin}" "${tgt_bin}" || \
        { rpc_error "failed to mv '${src_bin}' to '${tgt_bin}'"; continue; }

      rpc_exec systemctl -l start "${service_name}" || \
        { rpc_error "failed to start ${service_name}"; continue; }
    fi
  done <"${TEMP_FILE_LIST}"
done

exit 0
