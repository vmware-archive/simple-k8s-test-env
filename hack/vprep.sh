#!/bin/sh

set -o pipefail

export GOVC_VM=/SDDC-Datacenter/vm/Workloads/photon2

#govc vm.power -off "${GOVC_VM}" >/dev/null 2>&1

# Revert the VM to the snapshot that includes the SSH key.
echo "reverting the VM..."
govc snapshot.revert ssh 1>/dev/null

# Power on the VM
echo "powering on the VM..."
govc vm.power -on "${GOVC_VM}" 1>/dev/null

# Wait for the VM to be powered on.
echo "waiting for the VM to complete the power operation..."
govc object.collect "${GOVC_VM}" -runtime.powerState poweredOn 1>/dev/null

# Wait for the VM's IP to show up.
echo "waiting for the VM to report its IP address..."
if ! VM_IP=$(govc vm.ip -vm.ipath "${GOVC_VM}" -wait 5m); then
  q="${?}"; echo "failed to get VM IP address" 2>&1; exit "${q}"
fi

MYTEMP=$(mktemp -d)
SCRIPT_DIR="$(dirname "${0}")"

# Generate a new CA for the cluster.
export TLS_CA_CRT="${TLS_CA_CRT:-${MYTEMP}/ca.crt}"
export TLS_CA_KEY="${TLS_CA_KEY:-${MYTEMP}/ca.key}"
if [ ! -f "${TLS_CA_CRT}" ] || [ ! -f "${TLS_CA_KEY}" ]; then
  echo "generating x509 self-signed certificate authority..."
  "${SCRIPT_DIR}"/new-ca.sh >/dev/null 2>&1 || exit 1
fi

# Generate a new cert/key pair for the K8s admin user.
export TLS_CRT="${TLS_CRT:-${MYTEMP}/k8s-admin.crt}"
export TLS_KEY="${TLS_KEY:-${MYTEMP}/k8s-admin.key}"
if [ ! -f "${TLS_CRT}" ] || [ ! -f "${TLS_KEY}" ]; then
  echo "generating x509 cert/key pair for the k8s admin user..."
  TLS_COMMON_NAME="admin" \
    TLS_CRT_OUT="${TLS_CRT}" \
    TLS_KEY_OUT="${TLS_KEY}" \
    "${SCRIPT_DIR}"/new-cert.sh >/dev/null 2>&1 || exit 1
fi

# Generate a new kubeconfig for the K8s admin user.
export KUBECONFIG=${KUBECONFIG:-kubeconfig}
if [ ! -f "${KUBECONFIG}" ]; then
  echo "generating kubeconfig for the k8s-admin user..."
  SERVER="https://${VM_IP}:443" \
    USER="admin" \
    "${SCRIPT_DIR}"/new-kubeconfig.sh >/dev/null 2>&1 || exit 1
fi

# Ensure the rpctool program is up-to-date.
echo "making sure rpctool is up-to-date..."
ovf/rpctool/hack/make.sh

scp_to() {
  path="${1}"; shift
  scp -o ProxyCommand="ssh -W ${VM_IP}:22 $(whoami)@50.112.88.129" "${@}" root@"${VM_IP}":"${path}"
}

ssh_do() {
  ssh -o ProxyCommand="ssh -W ${VM_IP}:22 $(whoami)@50.112.88.129" root@"${VM_IP}" "${@}"
}

# Use SSH and SCP to configure the host.
#scp_to /etc/ssl/ca.crt "${TLS_CA_CRT}"
#scp_to /etc/ssl/ca.key "${TLS_CA_KEY}"
#ssh_do chmod 0444 /etc/ssl/ca.crt /etc/ssl/ca.key
ssh_do mkdir -p /var/lib/yakity
scp_to /var/lib/yakity/ yakity.sh
scp_to /var/lib/yakity/ ovf/rpctool/rpctool
ssh_do chmod 0755 /var/lib/yakity/rpctool
scp_to /var/lib/yakity/ ovf/*.sh
scp_to /var/lib/yakity/ ovf/yakity.service
ssh_do chmod 0755 /var/lib/yakity/*.sh
ssh_do systemctl -l enable /var/lib/yakity/yakity.service
#ssh_do systemctl -l --no-block start yakity

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

