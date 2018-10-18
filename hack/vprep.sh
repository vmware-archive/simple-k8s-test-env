#!/bin/sh

set -e
set -o pipefail

script_dir=$(python -c "import os; print(os.path.realpath('$(dirname "${0}")'))")
target_os=centos

case "${target_os}" in
photon)
  export GOVC_VM=/SDDC-Datacenter/vm/Workloads/photon2
  seal_script="${script_dir}/photon/photon-seal.sh"
  snapshot=ssh
  ;;
centos)
  export GOVC_VM=/SDDC-Datacenter/vm/Workloads/yakity-centos
  seal_script="${script_dir}/centos/centos-seal.sh"
  snapshot=rpctool
  ;;
*)
  echo "invalid target os: ${target_os}" 1>&2; exit 1
esac

# Revert the VM to the snapshot that includes the SSH key.
echo "reverting the VM..."
govc snapshot.revert "${snapshot}" 1>/dev/null

# Set additional properties on the VM.
#govc vm.change -e "guestinfo.yakity.VSPHERE_PASSWORD='${VSPHERE_PASSWORD}'"

# Power on the VM
echo "powering on the VM..."
govc vm.power -on "${GOVC_VM}" 1>/dev/null

# Wait for the VM to be powered on.
echo "waiting for the VM to complete the power operation..."
govc object.collect "${GOVC_VM}" \
  -runtime.powerState poweredOn 1>/dev/null

# Wait for the VM's IP to show up.
echo "waiting for the VM to report its IP address..."
if ! VM_IP=$(govc vm.ip -vm.ipath "${GOVC_VM}" -wait 5m); then
  q="${?}"; echo "failed to get VM IP address" 2>&1; exit "${q}"
fi

MYTEMP=$(mktemp -d)

if [ "${NEW_CA}" = "1" ]; then
  # Generate a new CA for the cluster.
  export TLS_CA_CRT="${TLS_CA_CRT:-${MYTEMP}/ca.crt}"
  export TLS_CA_KEY="${TLS_CA_KEY:-${MYTEMP}/ca.key}"
  if [ ! -f "${TLS_CA_CRT}" ] || [ ! -f "${TLS_CA_KEY}" ]; then
    echo "generating x509 self-signed certificate authority..."
    "${script_dir}"/new-ca.sh >/dev/null 2>&1
  fi

  # Generate a new cert/key pair for the K8s admin user.
  export TLS_CRT="${TLS_CRT:-${MYTEMP}/k8s-admin.crt}"
  export TLS_KEY="${TLS_KEY:-${MYTEMP}/k8s-admin.key}"
  if [ ! -f "${TLS_CRT}" ] || [ ! -f "${TLS_KEY}" ]; then
    echo "generating x509 cert/key pair for the k8s admin user..."
    TLS_COMMON_NAME="admin" \
      TLS_CRT_OUT="${TLS_CRT}" \
      TLS_KEY_OUT="${TLS_KEY}" \
      "${script_dir}"/new-cert.sh >/dev/null 2>&1
  fi

  # Generate a new kubeconfig for the K8s admin user.
  export KUBECONFIG=${KUBECONFIG:-kubeconfig}
  if [ ! -f "${KUBECONFIG}" ]; then
    echo "generating kubeconfig for the k8s-admin user..."
    SERVER="https://${VM_IP}:443" \
      USER="admin" \
      "${script_dir}"/new-kubeconfig.sh >/dev/null 2>&1
  fi
fi

# Ensure the rpctool program is up-to-date.
echo "make rpctool..."
"${script_dir}/"../ovf/rpctool/hack/make.sh 1>/dev/null

scp_to() {
  path="${1}"; shift
  scp -o ProxyCommand="ssh -W ${VM_IP}:22 $(whoami)@50.112.88.129" "${@}" \
    root@"${VM_IP}":"${path}"
}

ssh_do() {
  ssh -o ProxyCommand="ssh -W ${VM_IP}:22 $(whoami)@50.112.88.129" \
    root@"${VM_IP}" "${@}"
}

# Use SSH and SCP to configure the host.
ssh_do mkdir -p /var/lib/yakity

# Check to see if the rpc tool needs to be updated.
lcl_rpctool="${script_dir}/"../ovf/rpctool/rpctool
lcl_rpctool_hash=$({ shasum "${lcl_rpctool}" || sha1sum "${lcl_rpctool}"; } | \
                  awk '{print $1}')
rem_rpctool_hash=$(ssh_do sha1sum /var/lib/yakity/rpctool 2>/dev/null | \
  awk '{print $1}') || unset rem_rpctool_hash
printf 'rpctool\n  local  = %s\n  remote = %s\n  status = ' \
  "${lcl_rpctool_hash}" "${rem_rpctool_hash}"
if [ "${lcl_rpctool_hash}" = "${rem_rpctool_hash}" ]; then
  echo "up-to-date"
else
  echo "updating..."
  scp_to /var/lib/yakity/ "${lcl_rpctool}"
  ssh_do chmod 0755 /var/lib/yakity/rpctool
fi

scp_to /var/lib/yakity/ "${script_dir}/"../yakity.sh
scp_to /var/lib/yakity/ "${script_dir}/"../ovf/*.sh
scp_to /var/lib/yakity/ "${script_dir}/"../ovf/yakity.service
ssh_do 'chmod 0755 /var/lib/yakity/*.sh'
ssh_do systemctl -l enable /var/lib/yakity/yakity.service

if [ "${1}" = "seal" ]; then
  if [ -f "${seal_script}" ]; then
    scp_to /tmp/ "${seal_script}"
    ssh_do "sh -x /tmp/$(basename "${seal_script}")"
  fi
  echo "shutting down guest OS for OVF export..."
  govc vm.power -s "${GOVC_VM}" 1>/dev/null
  exit 0
fi

ssh_do systemctl -l --no-block start yakity

SSH_CMD="ssh -o ProxyCommand='ssh -W ${VM_IP}:22 $(whoami)@50.112.88.129' root@${VM_IP}"
printf '\nlog into host with the following command:\n\n  %s\n' "${SSH_CMD}"
if printf "%s" "${SSH_CMD}" | pbcopy >/dev/null 2>&1; then
  MOD_KEY="⌘"
elif printf "%s" "${SSH_CMD}" | xclip -selection clipboard >/dev/null 2>&1; then
  MOD_KEY="ctl"
fi
if [ -n "${MOD_KEY}" ]; then
  printf '\nthe above command is in the clipboard; use %s-v to paste the command into the terminal.\n' "${MOD_KEY}"
fi

