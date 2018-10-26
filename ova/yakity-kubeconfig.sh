#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to create and place an admin kubeconfig
# into the guestinfo property "yakity.kubeconfig". The kubeconfig will
# use the external FQDN of the cluster if set, otherwise the kubeconfig
# will list all of the control plane nodes.
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

is_controller() {
  echo "${1}" | grep -iq 'both\|controller'
}

govc_env="$(pwd)/.govc.env"

if val="$(get_config_val EXTERNAL_FQDN)" && [ -n "${val}" ]; then
  api_fqdn="${val}"
  echo "using external fqdn=${api_fqdn}"
elif val="$(get_config_val NODE_TYPE)" && is_controller "${val}"; then
  api_fqdn="$(ip route get 1 | awk '{print $NF;exit}')"
  echo "using own ipv4 address=${api_fqdn}"
elif [ -f "${govc_env}" ] && \
     val="$(get_config_val CLUSTER_UUIDS)" && [ -n "${val}" ]; then

  # Load the govc config into this script's process
  # shellcheck disable=SC1090
  set -o allexport && . "${govc_env}" && set +o allexport

  for type_and_uuid in ${val}; do
    _type="$(echo "${type_and_uuid}" | awk -F: '{print $1}')"
    if is_controller "${_type}"; then
      _uuid="$(echo "${type_and_uuid}" | awk -F: '{print $2}')"
      api_fqdn="$(govc vm.ip -vm.uuid "${_uuid}" -v4)"
      echo "using ipv4 address of first controller node=${api_fqdn}"
      break
    fi
  done
fi

if [ -z "${api_fqdn}" ]; then
  exit 0
fi

TLS_DEFAULT_BITS="$(get_config_val TLS_DEFAULT_BITS)"
TLS_DEFAULT_DAYS="$(get_config_val TLS_DEFAULT_DAYS)"
TLS_COUNTRY_NAME="$(get_config_val TLS_COUNTRY_NAME)"
TLS_STATE_OR_PROVINCE_NAME="$(get_config_val TLS_STATE_OR_PROVINCE_NAME)"
TLS_LOCALITY_NAME="$(get_config_val TLS_LOCALITY_NAME)"
TLS_ORG_NAME="$(get_config_val TLS_ORG_NAME)"
TLS_OU_NAME="$(get_config_val TLS_OU_NAME)"
TLS_EMAIL="$(get_config_val TLS_EMAIL)"

[ -z "${TLS_DEFAULT_BITS}" ] || export TLS_DEFAULT_BITS
[ -z "${TLS_DEFAULT_DAYS}" ] || export TLS_DEFAULT_DAYS
[ -z "${TLS_COUNTRY_NAME}" ] || export TLS_COUNTRY_NAME
[ -z "${TLS_STATE_OR_PROVINCE_NAME}" ] || export TLS_STATE_OR_PROVINCE_NAME
[ -z "${TLS_LOCALITY_NAME}" ] || export TLS_LOCALITY_NAME
[ -z "${TLS_ORG_NAME}" ] || export TLS_ORG_NAME
[ -z "${TLS_OU_NAME}" ] || export TLS_OU_NAME
[ -z "${TLS_OU_NAME}" ] || export TLS_OU_NAME
[ -z "${TLS_EMAIL}" ] || export TLS_EMAIL

export TLS_CA_CRT=/etc/ssl/ca.crt
export TLS_CA_KEY=/etc/ssl/ca.key

# Generate a new cert/key pair for the K8s admin user.
echo "generating x509 cert/key pair for the k8s admin user..."
TLS_CRT="$(mktemp)"; export TLS_CRT
TLS_KEY="$(mktemp)"; export TLS_KEY
TLS_COMMON_NAME="admin" \
  TLS_CRT_OUT="${TLS_CRT}" \
  TLS_KEY_OUT="${TLS_KEY}" \
  TLS_PLAIN_TEXT=true \
  ./new-cert.sh >/dev/null 2>&1

# Generate a new kubeconfig for the K8s admin user.
echo "generating kubeconfig for the k8s-admin user..."
secure_port="$(get_config_val SECURE_PORT)"
secure_port="${secure_port:-443}"
KUBECONFIG="$(mktemp)"; export KUBECONFIG
SERVER="https://${api_fqdn}:${secure_port}" \
  USER="admin" \
  ./new-kubeconfig.sh >/dev/null 2>&1

# Store the kubeconfig in guestinfo.yakity.KUBECONFIG.
rpc_set KUBECONFIG - <"${KUBECONFIG}"

exit 0
