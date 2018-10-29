#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
set -o pipefail

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

_uuids=$(govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.CLUSTER_UUIDS") | .Value')

skip_first=1
for _type_and_uuid in ${_uuids}; do
  [ -z "${skip_first}" ] || { unset skip_first && continue; }
  _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
  echo "destroying ${_type_and_uuid}"
  govc vm.destroy -vm.uuid "${_uuid}"
done

lb_arn=$(govc vm.info -vm.ipath "${GOVC_VM}" -json -e | \
  jq -r '.VirtualMachines[0].Config.ExtraConfig | .[] | select(.Key == "guestinfo.yakity.LOAD_BALANCER_ID") | .Value')
if [ "${lb_arn}" = "null" ]; then
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

govc vm.change -vm.ipath "${GOVC_VM}" -e "guestinfo.yakity.LOAD_BALANCER_ID=null"
