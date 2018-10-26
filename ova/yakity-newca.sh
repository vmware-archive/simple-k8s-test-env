#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to generate a self-signed CA if one does not
# exist or is not set in TLS_CA_PEM.
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

export TLS_CA_CRT=/etc/ssl/ca.crt
export TLS_CA_KEY=/etc/ssl/ca.key

if [ -f "${TLS_CA_CRT}" ] && [ -f "${TLS_CA_KEY}" ]; then
  echo "skipping ca generation; files exist"
  exit 0
fi
if [ -n "$(get_config_val TLS_CA_PEM)" ]; then
  echo "skipping ca generation; TLS_CA_PEM is set"
  exit 0
fi
num_nodes="$(get_config_val NUM_NODES)"
if [ "${num_nodes}" -gt "1" ] && \
   ! get_config_val CLONE_MODE | grep -iq '1|true'; then
  echo "skipping ca generation; CLONE_MODE is disabled"
  exit 0
fi

echo "generating x509 self-signed certificate authority..."

TLS_DEFAULT_BITS="$(get_config_val TLS_DEFAULT_BITS)"
TLS_DEFAULT_DAYS="$(get_config_val TLS_DEFAULT_DAYS)"
TLS_COUNTRY_NAME="$(get_config_val TLS_COUNTRY_NAME)"
TLS_STATE_OR_PROVINCE_NAME="$(get_config_val TLS_STATE_OR_PROVINCE_NAME)"
TLS_LOCALITY_NAME="$(get_config_val TLS_LOCALITY_NAME)"
TLS_ORG_NAME="$(get_config_val TLS_ORG_NAME)"
TLS_OU_NAME="$(get_config_val TLS_OU_NAME)"
TLS_EMAIL="$(get_config_val TLS_EMAIL)"
TLS_COMMON_NAME="$(get_config_val TLS_COMMON_NAME)"

[ -z "${TLS_DEFAULT_BITS}" ] || export TLS_DEFAULT_BITS
[ -z "${TLS_DEFAULT_DAYS}" ] || export TLS_DEFAULT_DAYS
[ -z "${TLS_COUNTRY_NAME}" ] || export TLS_COUNTRY_NAME
[ -z "${TLS_STATE_OR_PROVINCE_NAME}" ] || export TLS_STATE_OR_PROVINCE_NAME
[ -z "${TLS_LOCALITY_NAME}" ] || export TLS_LOCALITY_NAME
[ -z "${TLS_ORG_NAME}" ] || export TLS_ORG_NAME
[ -z "${TLS_OU_NAME}" ] || export TLS_OU_NAME
[ -z "${TLS_OU_NAME}" ] || export TLS_OU_NAME
[ -z "${TLS_EMAIL}" ] || export TLS_EMAIL
[ -z "${TLS_COMMON_NAME}" ] || export TLS_COMMON_NAME

# Generate a new CA for the cluster.
mkdir -p /etc/ssl; chmod 0755 /etc/ssl
TLS_PLAIN_TEXT=true ./new-ca.sh >/dev/null 2>&1
chmod 0644 /etc/ssl/ca.crt
chmod 0400 /etc/ssl/ca.key

exit 0
