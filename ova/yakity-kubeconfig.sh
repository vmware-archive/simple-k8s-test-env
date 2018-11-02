#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to create and place an admin kubeconfig
# into the guestinfo property "yakity.kubeconfig". The kubeconfig will
# use the external FQDN of the cluster if set, otherwise the kubeconfig
# will list all of the control plane nodes.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0
touch "${_done_file}"

if val="$(rpc_get EXTERNAL_FQDN)" && [ -n "${val}" ]; then
  api_fqdn="${val}"
  info "using external fqdn=${api_fqdn}"
else
  api_fqdn="$(ip route get 1 | awk '{print $NF;exit}')"
  info "using ipv4 address of controller node=${api_fqdn}"
fi

if [ -z "${api_fqdn}" ]; then
  warn "this node is unaware of a valid API server to use with a kubeconfig"
  exit 0
fi

TLS_DEFAULT_BITS="$(rpc_get TLS_DEFAULT_BITS)"
TLS_DEFAULT_DAYS="$(rpc_get TLS_DEFAULT_DAYS)"
TLS_COUNTRY_NAME="$(rpc_get TLS_COUNTRY_NAME)"
TLS_STATE_OR_PROVINCE_NAME="$(rpc_get TLS_STATE_OR_PROVINCE_NAME)"
TLS_LOCALITY_NAME="$(rpc_get TLS_LOCALITY_NAME)"
TLS_ORG_NAME="$(rpc_get TLS_ORG_NAME)"
TLS_OU_NAME="$(rpc_get TLS_OU_NAME)"
TLS_EMAIL="$(rpc_get TLS_EMAIL)"

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
info "generating x509 cert/key pair for the k8s admin user..."
TLS_CRT="$(mktemp)"; export TLS_CRT
TLS_KEY="$(mktemp)"; export TLS_KEY
TLS_COMMON_NAME="admin" \
  TLS_ORG_NAME="system:masters" \
  TLS_SAN=false \
  TLS_CRT_OUT="${TLS_CRT}" \
  TLS_KEY_OUT="${TLS_KEY}" \
  TLS_PLAIN_TEXT=true \
  ./new-cert.sh

# Generate a new kubeconfig for the K8s admin user.
info "generating kubeconfig for the k8s-admin user..."
KUBECONFIG="$(mktemp)"; export KUBECONFIG
secure_port="$(rpc_get SECURE_PORT)"
secure_port="${secure_port:-443}"
SERVER="https://${api_fqdn}:${secure_port}" \
  USER="admin" \
  ./new-kubeconfig.sh

# Store the kubeconfig in guestinfo.yakity.KUBECONFIG.
rpc_set KUBECONFIG - <"${KUBECONFIG}"

exit 0
