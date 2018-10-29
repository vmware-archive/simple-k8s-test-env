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

if val="$(rpc_get EXTERNAL_FQDN)" && [ -n "${val}" ]; then
  api_fqdn="${val}"
  info "using external fqdn=${api_fqdn}"
elif is_controller "$(rpc_get NODE_TYPE)"; then
  api_fqdn="$(ip route get 1 | awk '{print $NF;exit}')"
  info "using own ipv4 address=${api_fqdn}"
else
  api_fqdn="$(get_controller_ipv4_addrs | head -n 1)"
  info "using ipv4 address of first controller node=${api_fqdn}"
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
secure_port="$(rpc_get SECURE_PORT)"
secure_port="${secure_port:-443}"
KUBECONFIG="$(mktemp)"; export KUBECONFIG
SERVER="https://${api_fqdn}:${secure_port}" \
  USER="admin" \
  ./new-kubeconfig.sh

# Store the kubeconfig in guestinfo.yakity.KUBECONFIG.
rpc_set KUBECONFIG - <"${KUBECONFIG}"

# If the govc environment file is available then update the VM's annotation
# (the notes section) with a small script that may be used to fetch a
# valid kubeconfig for the cluster.
govc_env="$(pwd)/.govc.env"
if [ -f "${govc_env}" ]; then
  # Load the govc config into this script's process
  # shellcheck disable=SC1090
  set -o allexport && . "${govc_env}" && set +o allexport

  # Get the VM's UUID.ls /va
  self_uuid="$(get_self_uuid)"

  # Update the VM's annotation to reflect the "govc" command used to obtain
  # the kubeconfig.
  vsphere_server="$(rpc_get VSPHERE_SERVER)"
  vsphere_server="${vsphere_server:-VSPHERE_SERVER}"
  vsphere_server_port="$(rpc_get VSPHERE_SERVER_PORT)"
  vsphere_server_port="${vsphere_server_port:-443}"
  govc_url="${vsphere_server}:${vsphere_server_port}"
  get_kubeconfig_script="$(mktemp)"
  cat <<EOF >"${get_kubeconfig_script}"
_i=\$(govc vm.info -u "${govc_url}" -k -vm.uuid "${self_uuid}" -e) && \\
_l=\$(echo "\${_i}" | grep -n yakity.KUBECONFIG | cut -d: -f 1) && \\
echo "\${_i}" | sed -n "\${_l}"',/^\$/p' | sed -e '1 s/^.\\{0,\\}\$/apiVersion: v1/' -e '\$d'
EOF
  info "wrote get-kubeconfig script to ${get_kubeconfig_script}"
  govc vm.change -vm.uuid "${self_uuid}" \
    -annotation "$(cat "${get_kubeconfig_script}")" || \
    error "failed to set vm's annotation to get-kubeconfig script"
fi

exit 0
