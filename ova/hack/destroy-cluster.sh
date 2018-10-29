#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
set -o pipefail

[ -n "${1}" ] || { echo "usage: ${0} VM_UUID" 1>&2; exit 1; }
_vm_uuid="${1}"

_cluster_uuids=$(govc vm.info -vm.uuid "${_vm_uuid}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.CLUSTER_UUIDS") | .Value')

lb_arn=$(govc vm.info -vm.uuid "${_vm_uuid}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.LOAD_BALANCER_ID") | .Value')

skip_first=1
for _type_and_uuid in ${_cluster_uuids}; do
  if [ "${KEEP_FIRST}" = "true" ]; then
    [ -z "${skip_first}" ] || { unset skip_first && continue; }
  fi
  _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
  echo "destroying ${_type_and_uuid}"
  govc vm.destroy -vm.uuid "${_uuid}"
done

if [ -z "${lb_arn}" ] || [ "${lb_arn}" = "null" ]; then
  exit 0
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws program not found; unable to destroy load-balancer ${lb_arn}"
  exit 0
fi

lb_tgt_grp_arns=$(aws elbv2 describe-target-groups | \
  jq -r '.TargetGroups | .[] | select(.LoadBalancerArns != null) | select(any(.LoadBalancerArns[]; . == "'"${lb_arn}"'")) | .TargetGroupArn')

echo "deleting load balancer ${lb_arn}"
aws elbv2 delete-load-balancer --load-balancer-arn "${lb_arn}"

echo "waiting for load balancer to be deleted"
aws elbv2 wait load-balancers-deleted --load-balancer-arns ${lb_arn}

for arn in ${lb_tgt_grp_arns}; do
  echo "deleting target group ${arn}"
  aws elbv2 delete-target-group --target-group-arn "${arn}"
done

govc vm.change -vm.uuid "${_vm_uuid}" -e "guestinfo.yakity.LOAD_BALANCER_ID=null"
