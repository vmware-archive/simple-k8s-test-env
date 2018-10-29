#!/bin/sh

set -e
set -o pipefail

LINUX_DISTRO=${LINUX_DISTRO:-centos}

script_dir=$(python -c "import os; print(os.path.realpath('$(dirname "${0}")'))")

case "${LINUX_DISTRO}" in
photon)
  seal_script="${script_dir}/photon/photon-seal.sh"
  export GOVC_VM=${GOVC_VM:-/SDDC-Datacenter/vm/Workloads/photon2}
  SNAPSHOT_NAME=${SNAPSHOT_NAME:-bin}
  ;;
centos)
  seal_script="${script_dir}/centos/centos-seal.sh"
  export GOVC_VM=${GOVC_VM:-/SDDC-Datacenter/vm/Workloads/yakity-centos}
  SNAPSHOT_NAME=${SNAPSHOT_NAME:-bin}
  ;;
*)
  echo "invalid target os: ${LINUX_DISTRO}" 1>&2; exit 1
esac

# Revert the VM to the snapshot that includes the SSH key.
echo "reverting the VM..."
govc snapshot.revert "${SNAPSHOT_NAME}" 1>/dev/null

# Set additional properties on the VM.
if echo "${CREATE_LOAD_BALANCER}" | grep -iq '1\|true'; then
  CREATE_LOAD_BALANCER=true
else
  CREATE_LOAD_BALANCER=false
  AWS_ACCESS_KEY_ID=false
  AWS_SECRET_ACCESS_KEY=false
  AWS_DEFAULT_REGION=false
fi

govc vm.change -annotation " "
govc vm.change -e "guestinfo.yakity.EXTERNAL_FQDN=null"
govc vm.change -e "guestinfo.yakity.VSPHERE_SERVER=${VSPHERE_SERVER}"
govc vm.change -e "guestinfo.yakity.VSPHERE_USER=${VSPHERE_USER}"
govc vm.change -e "guestinfo.yakity.VSPHERE_PASSWORD=${VSPHERE_PASSWORD}"
govc vm.change -e "guestinfo.yakity.BOOTSTRAP_CLUSTER=${BOOTSTRAP_CLUSTER:-false}"
govc vm.change -e "guestinfo.yakity.SYSPREP=${SYSPREP:-false}"
govc vm.change -e "guestinfo.yakity.CLOUD_PROVIDER_TYPE=${CLOUD_PROVIDER_TYPE:-External}"
govc vm.change -e "guestinfo.yakity.HOST_FQDN=${HOST_FQDN:-${LINUX_DISTRO}.yakity}"
govc vm.change -e "guestinfo.yakity.NODE_TYPE=${NODE_TYPE:-controller}"
govc vm.change -e "guestinfo.yakity.NUM_NODES=${NUM_NODES:-1}"
govc vm.change -e "guestinfo.yakity.NUM_CONTROLLERS=${NUM_CONTROLLERS:-1}"
govc vm.change -e "guestinfo.yakity.NUM_BOTH=${NUM_BOTH:-0}"
govc vm.change -e "guestinfo.yakity.CREATE_LOAD_BALANCER=${CREATE_LOAD_BALANCER:-false}"
govc vm.change -e "guestinfo.yakity.AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}"
govc vm.change -e "guestinfo.yakity.AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}"
govc vm.change -e "guestinfo.yakity.AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}"

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

# Ensure the govc program is available.
echo "make govc..."
make -C "${script_dir}/.." govc-linux-amd64 1>/dev/null

# Ensure the rpctool program is available.
echo "make rpctool..."
if docker version >/dev/null 2>&1; then
  "${script_dir}/"../rpctool/hack/make.sh 1>/dev/null
else
  GOOS=linux make -C "${script_dir}/"../rpctool 1>/dev/null
fi

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
ssh_do mkdir -p /var/lib/yakity /opt/bin

# Check to see if the govc program needs to be updated.
lcl_govc="${script_dir}/"../govc-linux-amd64
lcl_govc_hash=$({ shasum "${lcl_govc}" || sha1sum "${lcl_govc}"; } | \
                  awk '{print $1}')
rem_govc_hash=$(ssh_do sha1sum /opt/bin/govc 2>/dev/null | \
  awk '{print $1}') || unset rem_govc_hash
printf 'govc\n  local  = %s\n  remote = %s\n  status = ' \
  "${lcl_govc_hash}" "${rem_govc_hash}"
if [ "${lcl_govc_hash}" = "${rem_govc_hash}" ]; then
  echo "up-to-date"
else
  echo "updating..."
  scp_to /opt/bin/ "${lcl_govc}"
  ssh_do chmod 0755 /opt/bin/govc
fi

# Check to see if the rpctool program needs to be updated.
lcl_rpctool="${script_dir}/"../rpctool/rpctool
lcl_rpctool_hash=$({ shasum "${lcl_rpctool}" || sha1sum "${lcl_rpctool}"; } | \
                  awk '{print $1}')
rem_rpctool_hash=$(ssh_do sha1sum /opt/bin/rpctool 2>/dev/null | \
  awk '{print $1}') || unset rem_rpctool_hash
printf 'rpctool\n  local  = %s\n  remote = %s\n  status = ' \
  "${lcl_rpctool_hash}" "${rem_rpctool_hash}"
if [ "${lcl_rpctool_hash}" = "${rem_rpctool_hash}" ]; then
  echo "up-to-date"
else
  echo "updating..."
  scp_to /opt/bin/ "${lcl_rpctool}"
  ssh_do chmod 0755 /opt/bin/rpctool
fi

scp_to /var/lib/yakity/ \
  "${script_dir}/../../yakity.sh" \
  "${script_dir}/../yakity.service" \
  "${script_dir}/../yakity-config-keys.env" \
  "${script_dir}/../yakity-ca.sh" \
  "${script_dir}/../yakity-cluster.sh" \
  "${script_dir}/../yakity-common.sh" \
  "${script_dir}/../yakity-guestinfo.sh" \
  "${script_dir}/../yakity-hostname.sh" \
  "${script_dir}/../yakity-kubeconfig.sh" \
  "${script_dir}/../yakity-load-balancer.sh" \
  "${script_dir}/../yakity-ssh.sh" \
  "${script_dir}/../yakity-vsphere.sh" \
  "${script_dir}/new-ca.sh" \
  "${script_dir}/new-cert.sh" \
  "${script_dir}/new-kubeconfig.sh" \
  "${script_dir}/../kube-update/kube-update.sh" \
  "${script_dir}/../kube-update/kube-update.service"
scp_to /var/lib/yakity/yakity-sysprep.sh \
  "${script_dir}/../sysprep/sysprep-${LINUX_DISTRO}.sh"
ssh_do 'chmod 0755 /var/lib/yakity/*.sh'
ssh_do systemctl -l enable /var/lib/yakity/yakity.service \
                           /var/lib/yakity/kube-update.service

if [ "${1}" = "seal" ]; then
  if [ -f "${seal_script}" ]; then
    scp_to /tmp/ "${seal_script}"
    ssh_do "sh -x /tmp/$(basename "${seal_script}")"
  fi
  echo "shutting down guest OS for OVF export..."
  govc vm.power -s "${GOVC_VM}" 1>/dev/null
  exit 0
fi

ssh_do systemctl -l --no-block start yakity kube-update
ssh_do 'rm -f /root/.bash_history && history -c'

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

