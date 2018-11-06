#!/bin/sh

# Yakity
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to generate a self-signed CA if one does not
# exist or is not set in TLS_CA_PEM.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0
touch "${_done_file}"

export TLS_CA_CRT=/etc/ssl/ca.crt
export TLS_CA_KEY=/etc/ssl/ca.key
mkdir -p /etc/ssl && chmod 0755 /etc/ssl

generate_ca() {
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
  ./new-ca.sh
}

if val="$(rpc_get TLS_CA_PEM)" && [ -n "${val}" ]; then
  info "using CA from TLS_CA_PEM..."
  echo "${val}" | unmangle_pem | openssl x509 1>"${TLS_CA_CRT}"
  echo "${val}" | unmangle_pem | openssl  rsa 1>"${TLS_CA_KEY}"
else
  info "generating x509 self-signed certificate authority..."
  generate_ca
fi

chmod 0644 "${TLS_CA_CRT}"
chmod 0400 "${TLS_CA_KEY}"
rpc_set TLS_CA_PEM - <"${TLS_CA_CRT}"
openssl x509 -noout -text <"${TLS_CA_CRT}"

exit 0

