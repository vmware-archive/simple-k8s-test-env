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

ssh_prv_key="$(mktemp)"
govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.SSH_PRV_KEY") | .Value' \
  >"${ssh_prv_key}"

vm_ip="$(govc vm.ip -vm.ipath "${GOVC_VM}" -v4 -n ethernet-0)"
ssh -i "${ssh_prv_key}" \
    -o ProxyCommand="ssh -W ${vm_ip}:22 $(whoami)@50.112.88.129" "root@${vm_ip}"
