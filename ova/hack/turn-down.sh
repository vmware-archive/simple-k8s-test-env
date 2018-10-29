#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
set -o pipefail

LINUX_DISTRO="${1:-${LINUX_DISTRO}}"
LINUX_DISTRO="${LINUX_DISTRO:-photon}"
case "${LINUX_DISTRO}" in
photon)
  GOVC_VM="${GOVC_VM:-${GOVC_FOLDER}/photon2}"
  ;;
centos)
  GOVC_VM="${GOVC_VM:-${GOVC_FOLDER}/yakity-centos}"
  ;;
*)
  echo "invalid target os: ${LINUX_DISTRO}" 1>&2; exit 1
esac

_vm_uuid=$(govc vm.info -vm.ipath "${GOVC_VM}" | \
  grep -i uuid | \
  awk '{print $2}')

KEEP_FIRST=true "$(dirname "${0}")"/destroy-cluster.sh "${_vm_uuid}"
