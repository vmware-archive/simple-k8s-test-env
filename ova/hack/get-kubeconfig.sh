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

is_controller() {
  echo "${1}" | grep -iq 'both\|controller'
}

_uuids=$(govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.CLUSTER_UUIDS") | .Value')

for _type_and_uuid in ${_uuids}; do
  _type="$(echo "${_type_and_uuid}" | awk -F: '{print $1}')"
  if is_controller "${_type}"; then
    _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
    govc vm.info -vm.uuid "${_uuid}" -json -e | \
      jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.KUBECONFIG") | .Value'
    exit 0
  fi
done
