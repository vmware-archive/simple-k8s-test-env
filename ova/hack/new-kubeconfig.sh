#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# USAGE: new-kubeconfig.sh
#    This script generates a kubeconfig.
#
# CONFIGURATION
#     This script is configured via the following environment
#     variables:
#

require() {
  val=$(eval "echo \${${1}}")
  [ -z "${val}" ] && echo "${1} required" 1>&2 && exit 1
}

require KUBECONFIG
require SERVER
require TLS_CA_CRT
require TLS_CRT
require TLS_KEY
require USER

CLUSTER="${CLUSTER:-kubernetes}"
CONTEXT="${CONTEXT:-default}"

cat <<EOF >"${KUBECONFIG}"
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: $(base64 -w0 <"${TLS_CA_CRT}")
    server: ${SERVER}
  name: ${CLUSTER}
contexts:
- context:
    cluster: ${CLUSTER}
    user: ${USER}
  name: ${CONTEXT}
current-context: ${CONTEXT}
kind: Config
preferences: {}
users:
- name: ${USER}
  user:
    client-certificate-data: $(base64 -w0 <"${TLS_CRT}")
    client-key-data: $(base64 -w0 <"${TLS_KEY}")
EOF

exit 0
