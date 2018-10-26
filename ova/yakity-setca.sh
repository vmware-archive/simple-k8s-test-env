#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Sets the CA public certificate in the guestinfo property yakity.TLS_CA_PEM
# as a PEM encoded certificate, overriding the previous value that may have
# included both the public and private key pair.
#

set -e
set -o pipefail

# Add ${BIN_DIR} to the path
BIN_DIR="${BIN_DIR:-/opt/bin}"; mkdir -p "${BIN_DIR}"; chmod 0755 "${BIN_DIR}"
echo "${PATH}" | grep -qF "${BIN_DIR}" || export PATH="${BIN_DIR}:${PATH}"

# echo2 echoes the provided arguments to file descriptor 2, stderr.
echo2() { echo "${@}" 1>&2; }

# fatal echoes a string to stderr and then exits the program.
fatal() { exit_code="${2:-${?}}"; echo2 "${1}"; exit "${exit_code}"; }

# Ensure the rpctool program is available.
command -v rpctool >/dev/null 2>&1 || fatal "failed to find rpctool command"

rpc_set() {
  rpctool set "yakity.${1}" "${2}" || fatal "rpctool: set yakity.${1} failed"
}

get_config_val() {
  val="$(rpctool get "yakity.${1}")" || fatal "rpctool: get yakity.${1} failed"
  if [ -n "${val}" ]; then
    printf 'got config val\n  key = %s\n  src = %s\n' \
      "${1}" "guestinfo.yakity" 1>&2
    echo "${val}"
  else
    val="$(rpctool get.ovf "${1}")" || fatal "rpctool: get.ovf ${1} failed"
    if [ -n "${val}" ]; then
      printf 'got config val\n  key = %s\n  src = %s\n' \
        "${1}" "guestinfo.ovfEnv" 1>&2
      echo "${val}"
    fi
  fi
}

echo "setting /etc/ssl/ca.crt to yakity.TLS_CA_PEM"
rpc_set TLS_CA_PEM - </etc/ssl/ca.crt

exit 0
