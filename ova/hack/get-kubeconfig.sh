#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

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

is_controller() {
  echo "${1}" | grep -iq 'both\|controller'
}

get_kubeconfig() {
  _l=$(echo "${1}" | grep -n yakity.KUBECONFIG | cut -d: -f 1) && \
  echo "${1}" | sed -n "${_l}"',/^$/p' | sed -e '1 s/^.\{0,\}$/apiVersion: v1/' -e '$d'
}

_uuids=$(govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.CLUSTER_UUIDS") | .Value')

for _type_and_uuid in ${_uuids}; do
  _type="$(echo "${_type_and_uuid}" | awk -F: '{print $1}')"
  if is_controller "${_type}"; then
    _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
    get_kubeconfig "$(govc vm.info -vm.uuid "${_uuid}" -e)"
    exit 0
  fi
done

get_kubeconfig "$(govc vm.info -vm.ipath "${GOVC_VM}" -e)"
