#!/bin/sh

# simple-kubernetes-test-environment
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

# posix compliant
# verified by https://www.shellcheck.net

#
# Initializes a local environment at $HOME/.sk8/CLUSTER_ID for accessing 
# a remote Kubernetes cluster.
#

set -e
set -o pipefail

# Store the VM's UUID.
vm_uuid="${1}"

# echo2 echoes the provided arguments to stderr.
echo2() { echo "${@}" 1>&2; }

# printf2 prints the provided format and arguments to stderr.
# shellcheck disable=SC2059
printf2() { _f="${1}"; shift; printf "${_f}" "${@}" 1>&2; }

if [ "${#}" -lt "1" ]; then
  echo2 "usage: ${0} VM_UUID" && exit 1
fi

if ! command -v govc >/dev/null 2>&1; then
  echo2 "failed to detect the govc command" && exit 1
fi

rpc_get_one_line() {
  _vm_uuid="${1}"; _key="${2}"
  govc vm.info -vm.uuid "${_vm_uuid}" -e | \
    grep -F "${_key}" | \
    sed 's/^.\{0,\}'"${_key}"':[[:space:]]\{0,\}//'
}

rpc_get_multi_line() {
  _vm_uuid="${1}"; _key="${2}"; _end_patt="${3:-^$}"
  _i="$(govc vm.info -vm.uuid "${_vm_uuid}" -e)" && \
  _l=$(echo "${_i}" | grep -n "${_key}" | cut -d: -f 1) && \
  echo "${_i}" | \
    sed -n "${_l}"',/'"${_end_patt}"'/p' | \
    sed 's/^.\{0,\}'"${_key}"':[[:space:]]\{0,\}//'
}

rpc_get() {
  if [ "${#}" -eq "2" ]; then
    rpc_get_one_line "${@}"
  elif [ "${#}" -eq "3" ]; then
    rpc_get_multi_line "${@}"
  else
    return 2
  fi
}

is_file_empty() {
  [ ! -e "${1}" ] || [ "$({ tr -d '[:space:]' | wc -m; } <"${1}")" -eq "0" ]
}

# "${node_type}:${uuid}:${host_name}"
parse_member_info()      { echo "${2}" | awk -F: '{print $'"${1}"'}'; }
parse_member_node_type() { parse_member_info 1 "${1}"; }
parse_member_id()        { parse_member_info 2 "${1}"; }
parse_member_host_name() { parse_member_info 3 "${1}"; }

mkdir_and_chmod() { mkdir -p "${@}" && chmod 0755 "${@}"; }

echo2 "getting cluster information"

# Get the cluster ID.
printf2 '  % -30s' '* id'
cluster_id=$(rpc_get "${vm_uuid}" CLUSTER_ID)
cluster_id7="$(echo "${cluster_id}" | cut -c-7)"
echo2 'success!'

# Create the local environment.
sk8_dir="${HOME}/.sk8/${cluster_id7}"
mkdir_and_chmod "${sk8_dir}"
mkdir_and_chmod "${sk8_dir}/bin"
mkdir_and_chmod "${sk8_dir}/.cluster"
mkdir_and_chmod "${sk8_dir}/.load-balancer"
mkdir_and_chmod "${sk8_dir}/.ssh" && chmod 0700 "${sk8_dir}/.ssh"

# Save the full cluster ID.
cluster_id_file="${sk8_dir}/.cluster/id"
echo "${cluster_id}" >"${cluster_id_file}"

# Get the cluster members.
printf2 '  % -30s' '* members'
cluster_members_file="${sk8_dir}/.cluster/members"
if ! rpc_get "${vm_uuid}" CLUSTER_MEMBERS | \
  tr '[:space:]' '\n' 1>"${cluster_members_file}" || \
  is_file_empty "${cluster_members_file}"; then
  echo2 'failed!' && exit 1
fi
echo2 'success!'

# Save the cluster's SSH key.
printf2 '  % -30s' '* ssh key'
ident_file="${sk8_dir}/.ssh/id_rsa"
if ! rpc_get "${vm_uuid}" SSH_PRV_KEY \
  "-----END RSA PRIVATE KEY-----" 1>"${ident_file}" || \
  is_file_empty "${ident_file}"; then
  echo2 'failed!' && exit 1
fi
chmod 0600 "${ident_file}"
echo2 'success!'

# Save the cluster's kubeconfig.
printf2 '  % -30s' '* kubeconfig'
kubeconfig="${sk8_dir}/kubeconfig"
if ! rpc_get "${vm_uuid}" KUBECONFIG 'guestinfo.' | \
  sed '$d' 1>"${kubeconfig}" || \
  is_file_empty "${kubeconfig}"; then
  echo2 'failed!' && exit 1
fi
echo2 'success!'

# Save the cluster's load balancer ID
printf2 '  % -30s' '* load-balancer'
lb_id_file="${sk8_dir}/.load-balancer/id"
if val="$(rpc_get "${vm_uuid}" LOAD_BALANCER_ID)" && [ -n "${val}" ]; then
  echo "${val}" >"${lb_id_file}"
  echo2 'success!'
else
  echo2 'notfound'
fi

echo2
echo2 "generating cluster access"

# Write the cluster's SSH config.
printf2 '  % -30s' '* ssh config'
ssh_config="${sk8_dir}/.ssh/config"
cat <<EOF >"${ssh_config}"
ServerAliveInterval 300
TCPKeepAlive        no
UserKnownHostsFile  ${sk8_dir}/.ssh/known_hosts

EOF

if [ -n "${JUMP_HOST}" ]; then
  default_ssh_ident_file="${HOME}/.ssh/id_rsa"
  if [ ! -f "${default_ssh_ident_file}" ]; then
    default_ssh_ident_file="${HOME}/.ssh/id_dsa"
  fi
  cat <<EOF >>"${ssh_config}"
Host jump
  HostName     ${JUMP_HOST}
  Port         ${JUMP_HOST_PORT:-22}
  User         ${JUMP_HOST_USER:-$(whoami)}
  IdentityFile ${JUMP_HOST_IDENT_FILE:-${default_ssh_ident_file}}
EOF
fi

while read -r member; do
  member_id="$(parse_member_id "${member}")"
  member_host_name="$(parse_member_host_name "${member}")"
  member_ip=$(govc vm.ip \
    -vm.uuid "${member_id}" \
    -v4 -n ethernet-0 2>/dev/null) || continue
  cat <<EOF >>"${ssh_config}"
Host ${member_host_name}
  HostName      ${member_ip}
  Port          22
  User          root
  IdentityFile  ${ident_file}
EOF
  if [ -n "${JUMP_HOST}" ]; then
    echo '  ProxyCommand  ssh -q -W %h:%p jump' >>"${ssh_config}"
  fi
done <"${cluster_members_file}"
echo2 'success!'

echo2
echo2 "generating commands"

printf2 '  % -30s' '* ssh'
ssh_cmd="${sk8_dir}/ssh"
if sys_cmd="$(command -v ssh 2>/dev/null)"; then
  cat <<EOF >"${ssh_cmd}"
#!/bin/sh

# simple-kubernetes-test-environment
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

${sys_cmd} -F ${ssh_config} "\${@}"
EOF
  chmod 0755 "${ssh_cmd}"
  [ -e "${sk8_dir}/bin/ssh-${cluster_id7}" ] || \
    ln -s "${ssh_cmd}" "${sk8_dir}/bin/ssh-${cluster_id7}" >/dev/null 2>&1
fi
echo2 'success!'

printf2 '  % -30s' '* scp'
scp_cmd="${sk8_dir}/scp"
if sys_cmd="$(command -v scp 2>/dev/null)"; then
  cat <<EOF >"${scp_cmd}"
#!/bin/sh

# simple-kubernetes-test-environment
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

${sys_cmd} -F ${ssh_config} "\${@}"
EOF
  chmod 0755 "${scp_cmd}"
  [ -e "${sk8_dir}/bin/scp-${cluster_id7}" ] || \
    ln -s "${scp_cmd}" "${sk8_dir}/bin/scp-${cluster_id7}" >/dev/null 2>&1
fi
echo2 'success!'

printf2 '  % -30s' '* kubectl'
kubectl_cmd="${sk8_dir}/kubectl"
if sys_cmd="$(command -v kubectl)"; then
  cat <<EOF >"${kubectl_cmd}"
#!/bin/sh

# simple-kubernetes-test-environment
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

${sys_cmd} --kubeconfig "${kubeconfig}" "\${@}"
EOF
  chmod 0755 "${kubectl_cmd}"
  [ -e "${sk8_dir}/bin/kubectl-${cluster_id7}" ] || \
    ln -s "${kubectl_cmd}" "${sk8_dir}/bin/kubectl-${cluster_id7}" >/dev/null 2>&1
fi
echo2 'success!'

printf2 '  % -30s' '* turn-down'
turn_down_cmd="${sk8_dir}/turn-down"
cat <<EOF >"${turn_down_cmd}"
#!/bin/sh

# simple-kubernetes-test-environment
#
# Copyright (c) 2018 VMware, Inc. All Rights Reserved.
#
# This product is licensed to you under the Apache 2.0 license (the "License").
# You may not use this product except in compliance with the Apache 2.0 License.
#
# This product may include a number of subcomponents with separate copyright
# notices and license terms. Your use of these subcomponents is subject to the
# terms and conditions of the subcomponent's license, as noted in the LICENSE
# file.

set -o pipefail

# echo2 echoes the provided arguments to stderr.
echo2() { echo "\${@}" 1>&2; }

while read -r member; do
  [ -z "\${SKIP_FIRST}" ] || { unset SKIP_FIRST && continue; }
  member_id=\$(echo "\${member}" | awk -F: '{print \$2}')
  echo2 "destroying VM \${member}"
  govc vm.destroy -vm.uuid "\${member_id}"
done <"${cluster_members_file}"

[ -f "${lb_id_file}" ] || exit 0
load_balancer_id="\$(cat "${lb_id_file}")"
[ -n "\${load_balancer_id}" ]         || exit 0
[ ! "\${load_balancer_id}" = "null" ] || exit 0

if ! command -v aws >/dev/null 2>&1; then
  echo2 "failed to detect the aws command" && exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo2 "failed to detect the jq command" && exit 1
fi

target_group_ids=\$(aws elbv2 describe-target-groups | \
  jq -r '.TargetGroups | .[] | select(.LoadBalancerArns != null) | select(any(.LoadBalancerArns[]; . == "'"\${load_balancer_id}"'")) | .TargetGroupArn')

echo2 "deleting load balancer \${load_balancer_id}"
aws elbv2 delete-load-balancer --load-balancer-arn "\${load_balancer_id}"

echo2 "waiting for load balancer to be deleted"
aws elbv2 wait load-balancers-deleted --load-balancer-arns "\${load_balancer_id}"

for target_group_id in \${target_group_ids}; do
  echo2 "deleting target group \${target_group_id}"
  aws elbv2 delete-target-group --target-group-arn "\${target_group_id}"
done
EOF
chmod 0755 "${turn_down_cmd}"
[ -e "${sk8_dir}/bin/turn-down-${cluster_id7}" ] || \
    ln -s "${turn_down_cmd}" "${sk8_dir}/bin/turn-down-${cluster_id7}" >/dev/null 2>&1
echo2 'success!'

cat <<EOF 1>&2

cluster access is now enabled at ${sk8_dir}.
several aliases of common programs are available:

  * ssh-${cluster_id7}
  * scp-${cluster_id7}
  * kubectl-${cluster_id7}
  * turn-down-${cluster_id7}

to use the above programs, execute the following:

  export PATH="${sk8_dir}/bin:\${PATH}"

EOF
