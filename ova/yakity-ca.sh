#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to generate a self-signed CA if one does not
# exist or is not set in TLS_CA_PEM.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

export TLS_CA_CRT=/etc/ssl/ca.crt
export TLS_CA_KEY=/etc/ssl/ca.key

generate_ca() {
  if [ -f "${TLS_CA_CRT}" ] && [ -f "${TLS_CA_KEY}" ]; then
    info "skipping ca generation; files exist"
    exit 0
  fi
  if [ -n "$(rpc_get TLS_CA_PEM)" ]; then
    info "skipping ca generation; TLS_CA_PEM is set"
    exit 0
  fi
  num_nodes="$(rpc_get NUM_NODES)"
  if [ "${num_nodes}" -gt "1" ] && is_false "$(rpc_get BOOTSTRAP_CLUSTER)"; then
    info "skipping ca generation; NUM_NODES=${num_nodes} and BOOTSTRAP_CLUSTER=false"
    exit 0
  fi

  info "generating x509 self-signed certificate authority..."

  TLS_DEFAULT_BITS="$(rpc_get TLS_DEFAULT_BITS)"
  TLS_DEFAULT_DAYS="$(rpc_get TLS_DEFAULT_DAYS)"
  TLS_COUNTRY_NAME="$(rpc_get TLS_COUNTRY_NAME)"
  TLS_STATE_OR_PROVINCE_NAME="$(rpc_get TLS_STATE_OR_PROVINCE_NAME)"
  TLS_LOCALITY_NAME="$(rpc_get TLS_LOCALITY_NAME)"
  TLS_ORG_NAME="$(rpc_get TLS_ORG_NAME)"
  TLS_OU_NAME="$(rpc_get TLS_OU_NAME)"
  TLS_EMAIL="$(rpc_get TLS_EMAIL)"
  TLS_COMMON_NAME="$(rpc_get TLS_COMMON_NAME)"

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
  TLS_PLAIN_TEXT=true ./new-ca.sh
  chmod 0644 /etc/ssl/ca.crt
  chmod 0400 /etc/ssl/ca.key
}

case "${1}" in
generate)
  generate_ca
  ;;
set)
  info "setting self-signed-ca"
  rpc_set TLS_CA_PEM - <"${TLS_CA_CRT}"
  ;;
esac

exit 0

