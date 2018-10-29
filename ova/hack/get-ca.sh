#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
set -o pipefail

[ -n "${1}" ] || { echo "usage: ${0} VM_UUID" 1>&2; exit 1; }
_vm_uuid="${1}"

_i="$(govc vm.info -vm.uuid "${_vm_uuid}" -e)" && \
_l=$(echo "${_i}" | grep -n 'yakity\.TLS_CA_PEM' | cut -d: -f 1) && \
echo "${_i}" | \
  sed -n "${_l}"',/^$/p' | \
  sed -e '1 s/^.\{0,\}$/-----BEGIN CERTIFICATE-----/' -e '$d'
