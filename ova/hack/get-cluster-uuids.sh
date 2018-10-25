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

_uuids=$(govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.CLUSTER_UUIDS") | .Value')

for _type_and_uuid in ${_uuids}; do
  echo "${_type_and_uuid}"
done
