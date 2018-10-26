#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

LINUX_DISTRO="${1:-${LINUX_DISTRO}}"
LINUX_DISTRO="${LINUX_DISTRO:-centos}"
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

govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.TLS_CA_PEM") | .Value'
