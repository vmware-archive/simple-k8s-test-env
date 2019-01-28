#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

################################################################################
## destroy-force.sh NAME                                                      ##
##                                                                            ##
##   This script destroys a provisioned environment manually by:              ##
##                                                                            ##
##     1. Using curl to delete DNS resources.                                 ##
##     2. Using the AWS CLI to remove AWS resources.                          ##
##     3. Using the VMware GoVC CLI to remove vSphere resources.              ##
##     4. Removes local Terraform state.                                      ##
################################################################################

# The script requires two arguments, the type of cluster and its name.
if [ -z "${1}" ]; then
  echo "usage: ${0} TYPE NAME"
  exit 1
fi

TYPE="${1}"; shift
NAME="${1}"; shift

# Marking this as a dry run results in an actions that *would* occur
# simply being echoed to stdout.
if [ "${VSPHERE_DESTROY_FORCE}" = "dryrun" ]; then
  DRYRUN=true
fi

################################################################################
##                         AWS Load Balancer Resources                        ##
################################################################################

# Make sure the AWS environment variables are set.
export AWS_ACCESS_KEY_ID=${VSPHERE_AWS_ACCESS_KEY_ID}
export AWS_SECRET_ACCESS_KEY=${VSPHERE_AWS_SECRET_ACCESS_KEY}
export AWS_DEFAULT_REGION=${VSPHERE_AWS_REGION}

# Parses the ARNs of resources as a result of describing the tags for
# one or more ARNs.
get_arns_from_tag_descriptions() {
  if [ -z "$*" ]; then return; fi
  aws elbv2 describe-tags --resource-arns "$@" | \
    jq ".TagDescriptions | \
      map(select(any(.Tags[]; .Key == \"Cluster\" and \
      .Value == \"${TYPE}-${NAME}\" )))" | \
    jq ".[] | .ResourceArn" | \
    tr -d '"'
}

# Get the AWS load balancers.
get_lb_arns() {
  # shellcheck disable=SC2046
  get_arns_from_tag_descriptions \
    $(aws elbv2 describe-load-balancers | jq ".LoadBalancers | \
    map(select(any(.;.LoadBalancerName | \
    startswith(\"yaklb\")))) | \
    .[] | \
    .LoadBalancerArn" | tr -d '"')
}

# Get the AWS load balancer target groups.
get_lb_target_group_arns() {
  # shellcheck disable=SC2046
  get_arns_from_tag_descriptions \
    $(aws elbv2 describe-target-groups | jq ".TargetGroups | \
    map(select(any(.;.TargetGroupName | \
    startswith(\"yaklb\")))) | \
    .[] | \
    .TargetGroupArn" | tr -d '"')
}

# Get the allocation IDs for the AWS elastic IPs,
get_elastic_ip_allocation_ids() {
  aws ec2 describe-addresses | \
    jq ".Addresses | \
      map(select(any(.Tags[]; .Key == \"Cluster\" and \
      .Value == \"${TYPE}-${NAME}\" )))" | \
    jq ".[] | .AllocationId" | \
    tr -d '"'
}

# Get the load balancer ARNs.
echo
echo '# deleting AWS load balancer(s)'
if arns=$(get_lb_arns) && [ -n "${arns}" ]; then
  # Delete the load balancers.
  for arn in ${arns}; do
    if [ "${DRYRUN}" = "true" ]; then
      echo aws elbv2 delete-load-balancer --load-balancer-arn "${arn}"
    else
      echo "  - ${arn}"
      aws elbv2 delete-load-balancer --load-balancer-arn "${arn}"
    fi
  done

  # Wait until the load balancers are deleted.
  echo
  echo '# waiting for deletion of AWS load balancer(s)'
  if [ "${DRYRUN}" = "true" ]; then
    # shellcheck disable=SC2086
    echo aws elbv2 wait load-balancers-deleted --load-balancer-arns ${arns}
  else
    # shellcheck disable=SC2086
    aws elbv2 wait load-balancers-deleted --load-balancer-arns ${arns}
  fi
fi

# Delete the target groups.
echo
echo '# deleting AWS load balancer target group(s)'
if arns=$(get_lb_target_group_arns) && [ -n "${arns}" ]; then
  for arn in ${arns}; do
    if [ "${DRYRUN}" = "true" ]; then
      echo aws elbv2 delete-target-group --target-group-arn "${arn}"
    else
      echo "  - ${arn}"
      aws elbv2 delete-target-group --target-group-arn "${arn}"
    fi
  done
fi


################################################################################
##                             vSphere Resources                              ##
################################################################################

# Define the information used to access the vSphere server.
export GOVC_USERNAME=${GOVC_USERNAME:-${VSPHERE_USER}}
export GOVC_PASSWORD=${GOVC_PASSWORD:-${VSPHERE_PASSWORD}}
export GOVC_URL=${GOVC_URL:-${VSPHERE_SERVER}}
export GOVC_DEBUG=${GOVC_DEBUG:-false}

# Define the parent datacenter to limit the scope of the govc commands.
export GOVC_DATACENTER=${GOVC_DATACENTER:-SDDC-Datacenter}

# Define the parent folder to limit scope of the govc command.
GOVC_ROOT_FOLDER=${GOVC_ROOT_FOLDER:-"/${GOVC_DATACENTER}/vm/Workloads/yake2e/${TYPE}"}

# Define the folder that contains the VMs.
GOVC_VM_FOLDER=${GOVC_VM_FOLDER:-"${GOVC_ROOT_FOLDER}/${NAME}"}

# Define the parent resource pool to limit scope of the govc command.
GOVC_ROOT_RESOURCE_POOL=${GOVC_ROOT_RESOURCE_POOL:-"/${GOVC_DATACENTER}/host/Cluster-1/Resources/Compute-ResourcePool/yake2e/${TYPE}"}

# Define the parent resource pool to limit scope of the govc command
# when querying resource pools that match a name.
export GOVC_RESOURCE_POOL=${GOVC_RESOURCE_POOL:-${GOVC_ROOT_RESOURCE_POOL}}

# Define the resource pool that contains the VMs.
GOVC_VM_RESOURCE_POOL=${GOVC_VM_RESOURCE_POOL:-${GOVC_ROOT_RESOURCE_POOL}/${NAME}}

# Destroy the VMs.
echo
echo '# deleting vSphere VM(s)'
if vms=$(govc ls "${GOVC_VM_FOLDER}") && [ -n "${vms}" ]; then
  IFS="$(printf '%b_' '\n')"; IFS="${IFS%_}" && \
  for vm in ${vms}; do
    if [ "${DRYRUN}" = "true" ]; then
      echo govc vm.destroy "'${vm}'"
    else
      echo "  - ${vm}"
      govc vm.destroy "${vm}"
    fi
  done
fi

# Destroy the folder.
echo
echo '# deleting vSphere folder(s)'
if govc object.collect "${GOVC_VM_FOLDER}" >/dev/null 2>&1; then
  if [ "${DRYRUN}" = "true" ]; then
    echo govc object.destroy "'${GOVC_VM_FOLDER}'"
  else
    echo "  - ${GOVC_VM_FOLDER}"
    STDOUT=$(govc object.destroy "${GOVC_VM_FOLDER}" 2>&1)
    echo "${STDOUT}" | grep '... OK$' >/dev/null 2>&1; MATCH_1=$?
    echo "${STDOUT}" | grep 'not found$' >/dev/null 2>&1; MATCH_2=$?
    if [ "${MATCH_1}" -ne "0" ] && [ "${MATCH_2}" -ne "0" ]; then
      echo "${STDOUT}"
    fi
  fi
fi

# Destroy the resource pool.
echo
echo '# deleting vSphere resource pool(s)'
if govc object.collect "${GOVC_VM_RESOURCE_POOL}" >/dev/null 2>&1; then
  if [ "${DRYRUN}" = "true" ]; then
    echo govc pool.destroy "'${GOVC_VM_RESOURCE_POOL}'"
  else
    echo "  - ${GOVC_VM_RESOURCE_POOL}"
    govc pool.destroy "${GOVC_VM_RESOURCE_POOL}"
  fi
fi

# If the environment variable VSPHERE_TFSTATE_PATH is set then
# check to see if it is a valid file path, and if so, treat it
# as the Terraform file/directory to be removed.
echo
echo '# deleting Terraform state'
if [ -e "${VSPHERE_TFSTATE_PATH}" ]; then
  if [ "${DRYRUN}" = "true" ]; then
    echo rm -fr "${VSPHERE_TFSTATE_PATH}"
  else
    echo "  - ${VSPHERE_TFSTATE_PATH}"
    rm -fr "${VSPHERE_TFSTATE_PATH}"
  fi
fi
