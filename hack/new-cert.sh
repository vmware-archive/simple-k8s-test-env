#!/bin/sh

# simple-kubernetes-test-environment
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
# USAGE: new-cert.sh [CN]
#    This script generates a PEM-formatted, certificate, signed by
#    TLS_CA_CRT/TLS_CA_KEY.
#
#    The generated key and certificate are printed to STDOUT unless
#    TLS_KEY_OUT and TLS_CRT_OUT are both set or TLS_PEM_OUT is set.
#
# CONFIGURATION
#     This script is configured via the following environment
#     variables:
#

# The paths to the TLS CA crt and key files used to sign the
# generated certificate signing request (CSR).
TLS_CA_CRT=${TLS_CA_CRT:-ca.crt}
TLS_CA_KEY=${TLS_CA_KEY:-ca.key}

# The paths to the generated key and certificate files.
# If TLS_KEY_OUT, TLS_CRT_OUT, and TLS_PEM_OUT are all unset then
# the generated key and certificate are printed to STDOUT.
#TLS_KEY_OUT=server.key
#TLS_CRT_OUT=server.crt

# The path to the combined key and certificate file.
# Setting this value overrides TLS_KEY_OUT and TLS_CRT_OUT.
#TLS_PEM_OUT=server.pem

# The strength of the generated certificate
TLS_DEFAULT_BITS=${TLS_DEFAULT_BITS:-2048}

# The number of days until the certificate expires. The default
# value is 10 years.
TLS_DEFAULT_DAYS=${TLS_DEFAULT_DAYS:-3650}

# The components that make up the certificate's distinguished name.
TLS_COUNTRY_NAME=${TLS_COUNTRY_NAME:-US}
TLS_STATE_OR_PROVINCE_NAME=${TLS_STATE_OR_PROVINCE_NAME:-California}
TLS_LOCALITY_NAME=${TLS_LOCALITY_NAME:-Palo Alto}
TLS_ORG_NAME=${TLS_ORG_NAME:-VMware}
TLS_OU_NAME=${TLS_OU_NAME:-CNX}
TLS_COMMON_NAME=${TLS_COMMON_NAME:-${1}}
TLS_EMAIL=${TLS_EMAIL:-cnx@vmware.com}

# Set to true to indicate the certificate is a CA.
TLS_IS_CA=${TLS_IS_CA:-FALSE}

# The certificate's key usage.
TLS_KEY_USAGE=${TLS_KEY_USAGE:-digitalSignature, keyEncipherment}

# The certificate's extended key usage string.
TLS_EXT_KEY_USAGE=${TLS_EXT_KEY_USAGE:-clientAuth, serverAuth}

# Set to false to disable subject alternative names (SANs).
TLS_SAN=${TLS_SAN:-true}

# A space-delimited list of FQDNs to use as SANs.
#TLS_SAN_DNS=

# A space-delimited list of IP addresses to use as SANs.
#TLS_SAN_IP=

# Verify that the CA has been provided.
if [ -z "${TLS_CA_CRT}" ] || [ -z "${TLS_CA_KEY}" ]; then
  echo "TLS_CA_CRT and TLS_CA_KEY required"
  exit 1
fi

# Make a temporary directory and switch to it.
OLDDIR=$(pwd)
MYTEMP=$(mktemp -d) && cd "$MYTEMP" || exit 1

# Returns the absolute path of the provided argument.
abs_path() {
  { [ "$(printf %.1s "${1}")" = "/" ] && echo "${1}"; } || echo "${OLDDIR}/${1}"
}

# Write the SSL config file to disk.
cat > ssl.conf <<EOF
[ req ]
default_bits           = ${TLS_DEFAULT_BITS}
default_days           = ${TLS_DEFAULT_DAYS}
encrypt_key            = no
default_md             = sha1
prompt                 = no
utf8                   = yes
distinguished_name     = dn
req_extensions         = ext
x509_extensions        = ext

[ dn ]
countryName            = ${TLS_COUNTRY_NAME}
stateOrProvinceName    = ${TLS_STATE_OR_PROVINCE_NAME}
localityName           = ${TLS_LOCALITY_NAME}
organizationName       = ${TLS_ORG_NAME}
organizationalUnitName = ${TLS_OU_NAME}
commonName             = ${TLS_COMMON_NAME}
emailAddress           = ${TLS_EMAIL}

[ ext ]
basicConstraints       = CA:$(echo "${TLS_IS_CA}" | tr '[:lower:]' '[:upper:]')
keyUsage               = ${TLS_KEY_USAGE}
extendedKeyUsage       = ${TLS_EXT_KEY_USAGE}
subjectKeyIdentifier   = hash
EOF

if [ "${TLS_SAN}" = "true" ] && \
   { [ -n "${TLS_SAN_DNS}" ] || [ -n "${TLS_SAN_IP}" ]; }; then
  cat >> ssl.conf <<EOF
subjectAltName         = @sans

# DNS.1     repeats the certificate's CN. Some clients have been known 
#           to ignore the subject if SANs are set.
# DNS.2-n-1 are additional DNS SANs parsed from TLS_SAN_DNS
#
# IP.1-n-1  are additional IP SANs parsed from TLS_SAN_IP
[ sans ]
DNS.1                  = ${TLS_COMMON_NAME}
EOF
  # Append any DNS SANs to the SSL config file.
  i=2 && for j in $TLS_SAN_DNS; do
    echo "DNS.${i}                  = $j" >> ssl.conf && i="$(( i+1 ))"
  done

  # Append any IP SANs to the SSL config file.
  i=1 && for j in $TLS_SAN_IP; do
    echo "IP.${i}                   = $j" >> ssl.conf && i="$(( i+1 ))"
  done
fi

if [ "${DEBUG}" = "true" ]; then cat ssl.conf; fi

# Generate a private key file.
openssl genrsa -out key.pem "${TLS_DEFAULT_BITS}" || exit "${?}"

# Generate a certificate CSR.
openssl req -config ssl.conf \
            -new \
            -key key.pem \
            -days "${TLS_DEFAULT_DAYS}" \
            -out csr.pem || exit "${?}"

# Sign the CSR with the provided CA.
CA_CRT=$(abs_path "${TLS_CA_CRT}")
CA_KEY=$(abs_path "${TLS_CA_KEY}")
openssl x509 -extfile ssl.conf \
             -extensions ext \
             -days "${TLS_DEFAULT_DAYS}" \
             -req \
             -in csr.pem \
             -CA "${CA_CRT}" \
             -CAkey "${CA_KEY}" \
             -CAcreateserial \
             -out crt.pem || exit "${?}"

# Generate a combined PEM file at TLS_PEM_OUT.
if [ -n "${TLS_PEM_OUT}" ]; then
  PEM_FILE=$(abs_path "${TLS_PEM_OUT}")
  mkdir -p "$(dirname "${PEM_FILE}")"
  cat key.pem > "${PEM_FILE}"
  cat crt.pem >> "${PEM_FILE}"
fi

# Copy the key and crt files to TLS_KEY_OUT and TLS_CRT_OUT.
if [ -n "${TLS_KEY_OUT}" ]; then
  KEY_FILE=$(abs_path "${TLS_KEY_OUT}")
  mkdir -p "$(dirname "${KEY_FILE}")"
  cp -f key.pem "${KEY_FILE}"
else
  cp -f key.pem "${OLDDIR}/${TLS_COMMON_NAME}.key"
fi

if [ -n "${TLS_CRT_OUT}" ]; then
  CRT_FILE=$(abs_path "${TLS_CRT_OUT}")
  mkdir -p "$(dirname "${CRT_FILE}")"
  cp -f crt.pem "${CRT_FILE}"
else
  cp -f crt.pem "${OLDDIR}/${TLS_COMMON_NAME}.crt"
fi

# Print the certificate's information if requested.
if [ "${TLS_PLAIN_TEXT}" = "true" ]; then
  echo && openssl x509 -in crt.pem -noout -text
fi

exit 0
