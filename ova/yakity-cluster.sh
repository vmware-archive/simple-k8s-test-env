#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to do one of two things:
#
#   1. Clone the primary node into the number of requested cluster nodes
#   2. Sysprep a cloned node
#
# If an OVA is deployed to provision a cluster, this service is
# responsible for figuring out the VM's UUID and then cloning it to
# the number of requested cluster nodes. On the cloned nodes this
# service will run a sysprep script that reverts the guest OS back to
# a clean state. The primary node will wait for this to happen and then
# set the appropriate GuestInfo properties on the cloned nodes and send
# them the power signal.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

get_vm_uuid() {
  govc vm.info -vm.ipath "${1}" -json | jq -r '.VirtualMachines[0].Config.Uuid'
}

get_moref_via_my_vm() {
  moref_type="$(jq -r '.VirtualMachines[0].${1}.Type' <self.json)" || \
    fatal "failed to get VM's ${1}'s moref type"
  moref_value="$(jq -r '.VirtualMachines[0].${1}.Value' <self.json)" || \
    fatal "failed to get VM's ${1}'s moref value"
  moref="${moref_type}:${moref_value}"
  govc ls -L "${moref}" || \
    fatal "failed to get VM's ${1}'s inventory path"
}

set_guestinfo() {
  _vm_uuid="${1}"
  _key="${2}"
  _val="${3}"
  govc vm.change \
    -vm.uuid "${_vm_uuid}" \
    -e "guestinfo.yakity.${_key}=${_val}" || \
    fatal "failed to set guestinfo.yakity.${_key} on ${_vm_uuid}"
}


power_on_vm() {
  govc vm.power -on -vm.uuid "${1}" || fatal "failed to power on ${1}"
}

CLONE_UUID_FILE="$(mktemp)";      export CLONE_UUID_FILE;
CLONE_UUID_LOCK="$(mktemp)";      export CLONE_UUID_LOCK;

create_clone() {
  _clone_node_type="${1}"
  _clone_name="${2}"
  _clone_fqdn="${3}"
  _clone_num_cpus="${4}"
  _clone_mem_mib="${5}"
  _clone_ipath="${6}"

  # Clone this VM.
  govc vm.clone \
    -vm "${GOVC_SELF}" \
    -on=false \
    -c "${_clone_num_cpus}" -m "${_clone_mem_mib}" \
    "${_clone_name}" || \
    fatal "failed to clone ${GOVC_SELF} to ${_clone_ipath}"

  # Get the clone's UUID and write it to the cluster file.
  _clone_uuid="$(get_vm_uuid "${_clone_ipath}")"

  cat <<EOF

================================================================================
clone uuid            = ${_clone_uuid}
clone name            = ${_clone_name}
clone inventory path  = ${_clone_ipath}
clone host fqdn       = ${_clone_fqdn}
clone node type       = ${_clone_node_type}
clone number of cpus  = ${_clone_num_cpus}
clone memory (GiB)    = ${_clone_mem_mib}
================================================================================

EOF

  # Write the clone's UUID to the UUID files using an exclusive lock in order
  # to prevent other create_clone jobs that have been background from
  # writing to the UUID file at the same time as this job.
  flock -x "${CLONE_UUID_LOCK}" \
    echo "${_clone_node_type}:${_clone_uuid}" >>"${CLONE_UUID_FILE}"

  # Update the clone's guestinfo to tell the clone that it has in fact
  # been cloned. This will cause this script to sysprep the clone when
  # it first boots.
  set_guestinfo "${_clone_uuid}" SYSPREP              "true"
  set_guestinfo "${_clone_uuid}" BOOTSTRAP_CLUSTER    "false"
  set_guestinfo "${_clone_uuid}" CREATE_LOAD_BALANCER "false"

  # Power on the clone so it can sysprep itself. The clone will power itself
  # off once the sysprep operation has completed.
  power_on_vm "${_clone_uuid}"

  # Wait for the VM to be powered off.
  govc object.collect "${_clone_ipath}" -runtime.powerState poweredOff || \
    fatal "failed to wait for ${_clone_ipath} to be powered off"

  # Update the clone's guestinfo with all of the config properties.
  set_guestinfo "${_clone_uuid}" NODE_TYPE         "${_clone_node_type}"
  set_guestinfo "${_clone_uuid}" HOST_FQDN         "${_clone_fqdn}"
  set_guestinfo "${_clone_uuid}" SSH_PUB_KEY       "${SSH_PUB_KEY}"
  set_guestinfo "${_clone_uuid}" ETCD_DISCOVERY    "${ETCD_DISCOVERY}"

  # Iterate over the configuration keys to set on the new VM.
  while IFS= read -r _key; do
    if _val="$(rpc_get "${_key}")" && [ -n "${_val}" ]; then
      set_guestinfo "${_clone_uuid}" "${_key}" "${_val}"
    fi
  done <yakity-config-keys.env
}

bootstrap_cluster() {
  govc_env="$(pwd)/.govc.env"
  [ -f "${govc_env}" ] || fatal "${govc_env} is missing"

  # Load the govc config into this script's process
  # shellcheck disable=SC1090
  set -o allexport && . "${govc_env}" && set +o allexport

  # Remove the .govc.env file since it's no longer needed. This ensures the
  # file is not on any of the clones as well.
  # TODO The removal of the .govc.env file has been disabled for now to
  #      give the kube-update service the ability to set guestinfo properties
  #      on all the nodes in the cluster.
  #rm -f "${govc_env}"

  # Get information about this VM.
  self_name="$(basename "${GOVC_SELF}")"
  host_name="$(hostname -s)"
  domain_name="$(hostname -d)"
  self_uuid="$(get_self_uuid)"

  # The SSH_PUB_KEYS value.
  SSH_PUB_KEY="$(rpc_get SSH_PUB_KEY)"
  export SSH_PUB_KEY

  # The type of node being cloned.
  self_node_type="$(get_self_node_type)"

  # The total number of nodes in the cluster.
  num_nodes="$(rpc_get NUM_NODES)"
  num_nodes="${num_nodes:-1}"
  
  # The number of nodes that are members of the control plane.
  num_controllers="$(rpc_get NUM_CONTROLLERS)"
  num_controllers="${num_controllers:-${num_nodes}}"

  # The number of controllers on which workloads can be scheduled.
  num_both="$(rpc_get NUM_BOTH)"
  num_both="${num_both:-0}"
  if [ "${num_both}" -gt "${num_controllers}" ]; then
    num_both="${num_controllers}"
  fi

  # The number of workers is the number of nodes less the number of controllers.
  num_workers=$((num_nodes-num_controllers))

  # Change this node's type to "controller" if this is a multi-node cluster
  # and no control plane / worker hybrids were requested.
  if [ "${num_nodes}" -gt "1" ] && [ "${num_both}" -eq "0" ]; then
    self_node_type=controller
    rpc_set NODE_TYPE "${self_node_type}"
    info "changed node type to 'controller' bc/ 'both' was not requested"
  fi

  # Generate a new etcd discovery URL and set it on this VM.
  ETCD_DISCOVERY="$(curl -sSL "https://discovery.etcd.io/new?size=${num_controllers}")" || \
    fatal "failed get get new etcd discovery URL"
  rpc_set "ETCD_DISCOVERY" "${ETCD_DISCOVERY}"
  export ETCD_DISCOVERY

  # Get the number of requested CPUs and amount of memory.
  num_cpus_ctl="$(rpc_get CLONE_NUM_CPUS_CONTROLLERS)"
  num_cpus_wrk="$(rpc_get CLONE_NUM_CPUS_WORKERS)"
  mem_gib_ctl="$(rpc_get CLONE_MEM_GB_CONTROLLERS)"
  mem_gib_wrk="$(rpc_get CLONE_MEM_GB_WORKERS)"
  
  num_cpus_ctl="${num_cpus_ctl:-2}"
  num_cpus_wrk="${num_cpus_wrk:-4}"
  mem_gib_ctl="${mem_gib_ctl:-4}"
  mem_gib_wrk="${mem_gib_wrk:-8}"
  mem_mib_ctl=$((mem_gib_ctl*1024))
  mem_mib_wrk=$((mem_gib_wrk*1024))

  # Get the resource totals.
  total_cpus_ctl="$((num_cpus_ctl*(num_controllers-num_both)))"
  total_mem_gib_ctl="$((mem_gib_ctl*(num_controllers-num_both)))"
  total_cpus_wrk="$((num_cpus_wrk*(num_both+num_workers)))"
  total_mem_gib_wrk="$((mem_gib_wrk*(num_both+num_workers)))"

  # Get the resource allotment for this VM.
  self_cpus="$(grep -c ^processor /proc/cpuinfo)"
  self_mem_kib="$(grep MemTotal /proc/meminfo | awk '{print $2}')"
  self_mem_mib="$(((self_mem_kib+1023)/1024))"
  self_mem_gib="$(((self_mem_mib+1023)/1024))"

  # Add this VM's resource allotment to the totals.
  total_cpus="$((self_cpus+total_cpus_ctl+total_cpus_wrk))"
  total_mem_gib="$((self_mem_gib+total_mem_gib_ctl+total_mem_gib_wrk))"

  # Adjust the totals by removing one controller/worker allotment
  # depending on the type of node this VM is.
  case "${self_node_type}" in
  both|worker)
    total_cpus="$((total_cpus-num_cpus_wrk))"
    total_mem_gib="$((total_mem_gib-mem_gib_wrk))"
    ;;
  controller)
    total_cpus="$((total_cpus-num_cpus_ctl))"
    total_mem_gib="$((total_mem_gib-mem_gib_ctl))"
    ;;
  esac

  # Figure out how many VMs are needed.
  i_ctl=1; i_wrk=1;
  num_controllers_to_clone="${num_controllers}"
  num_controllers_to_clone_as_both="${num_both}"
  num_workers_to_clone="${num_workers}"
  case "${self_node_type}" in
  both|controller)
    i_ctl=2
    num_controllers_to_clone="$((num_controllers_to_clone-1))"
    if [ "${self_node_type}" = "both" ]; then
      num_controllers_to_clone_as_both="$((num_controllers_to_clone_as_both-1))"
    fi
    ;;
  worker)
    i_wrk=2
    num_workers_to_clone="$((num_workers_to_clone-1))"
    ;;
  esac

  cat <<EOF

================================================================================
cluster etcd                             = ${ETCD_DISCOVERY}
================================================================================

================================================================================
cluster control plane nodes              = ${num_controllers}
  cluster that can schedule workloads    = ${num_both}
cluster worker nodes                     = ${num_workers}
================================================================================

================================================================================
cluster total nodes                      = ${num_nodes}
cluster total cpus                       = ${total_cpus}
cluster total memory (GiB)               = ${total_mem_gib}
================================================================================

================================================================================
cluster num control plane nodes to clone = ${num_controllers_to_clone}
  cluster that can schedul workloads     = ${num_controllers_to_clone_as_both}
cluster num worker nodes to clone        = ${num_workers_to_clone}
================================================================================

EOF

  # Create the control plane nodes.
  i=0 && while [ "${i}" -lt "${num_controllers_to_clone}" ]; do
    clone_node_type=controller
    clone_name_suffix="$(printf 'c%02d' "${i_ctl}")"
    clone_name="${self_name}-${clone_name_suffix}"
    clone_fqdn="${host_name}-${clone_name_suffix}.${domain_name}"
    clone_ipath="${GOVC_FOLDER}/${clone_name}"
    clone_num_cpus="${num_cpus_ctl}"
    clone_mem_mib="${mem_mib_ctl}"
    if [ "${i}" -le "${num_controllers_to_clone_as_both}" ]; then
      clone_node_type=both
      clone_num_cpus="${num_cpus_wrk}"
      clone_mem_mib="${mem_mib_wrk}"
    fi

    # Create the clone.
    create_clone  "${clone_node_type}" \
                  "${clone_name}" \
                  "${clone_fqdn}" \
                  "${clone_num_cpus}" \
                  "${clone_mem_mib}" \
                  "${clone_ipath}" &

    i="$((i+1))"
    i_ctl="$((i_ctl+1))"
  done

  # Create the worker nodes.
  i=0 && while [ "${i}" -lt "${num_workers_to_clone}" ]; do
    clone_node_type=worker
    clone_name_suffix="$(printf 'w%02d' "${i_wrk}")"
    clone_name="${self_name}-${clone_name_suffix}"
    clone_fqdn="${host_name}-${clone_name_suffix}.${domain_name}"
    clone_ipath="${GOVC_FOLDER}/${clone_name}"
    clone_num_cpus="${num_cpus_wrk}"
    clone_mem_mib="${mem_mib_wrk}"

    # Create the clone.
    create_clone  "${clone_node_type}" \
                  "${clone_name}" \
                  "${clone_fqdn}" \
                  "${clone_num_cpus}" \
                  "${clone_mem_mib}" \
                  "${clone_ipath}" &

    i="$((i+1))"
    i_wrk="$((i_wrk+1))"
  done

  # Wait on all of the clone jobs to complete.
  wait || fatal "clone job(s) failed"

  # Create a list of all the UUIDs of the VMs in this cluster.
  _cluster_uuids="${self_node_type}:${self_uuid}"
  while IFS= read -r _type_and_uuid; do
    _cluster_uuids="${_cluster_uuids} ${_type_and_uuid}"
  done <"${CLONE_UUID_FILE}"

  # Assign the list of cluster IDs to each node in the cluster so that nodes
  # are able to query vSphere about other nodes using unique IDs.
  for _type_and_uuid in ${_cluster_uuids}; do
    _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
    set_guestinfo "${_uuid}" CLUSTER_UUIDS "${_cluster_uuids}" &
  done

  # Wait on all of the set cluster ID jobs to complete.
  wait || fatal "set cluster UUID job(s) failed"

  # Power on all of the cloned VMs.
  while IFS= read -r _type_and_uuid; do
    _uuid="$(echo "${_type_and_uuid}" | awk -F: '{print $2}')"
    power_on_vm "${_uuid}" &
  done <"${CLONE_UUID_FILE}"

  # Wait on all of the power-on jobs to complete.
  wait || fatal "power-on job(s) failed"

  info "cluster bootstrap complete!"
}

# Check to see if the node should be sysprepped. If true then the sysprep
# script will shutdown the VM and nothing beyond this if block will be
# executed.
if is_true "$(rpc_get SYSPREP)"; then
  info "performing sysprep"
  rpc_set SYSPREP false
  ./yakity-sysprep.sh

# Check to see if a cluster should be bootstrapped.
elif is_true "$(rpc_get BOOTSTRAP_CLUSTER)"; then
  info "bootstrapping cluster"
  rpc_set BOOTSTRAP_CLUSTER false
  bootstrap_cluster

# If the VM's CLUSTER_UUIDS field is empty then set it to this VM's UUID.
elif [ -z "$(rpc_get CLUSTER_UUIDS)" ]; then
  self_type_and_uuid="$(get_self_node_type):$(get_self_uuid)"
  info "no cluster: assigning ${self_type_and_uuid} to CLUSTER_UUIDS"
  rpc_set CLUSTER_UUIDS "${self_type_and_uuid}"
fi

exit 0
