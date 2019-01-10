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
# Used by the sk8 service to extract the vSphere credentials from the
# OVF environment and then write the vSphere information about this VM
# to disk.
#

# Load the sk8 commons library.
# shellcheck disable=SC1090
. "$(pwd)/sk8-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0
touch "${_done_file}"

# Exit the script if the govc environment file already exists.
govc_env=".govc.env"
[ ! -f "${govc_env}" ] || exit 0

get_moref_via_my_vm() {
  type="${1}"
  json="${2}"
  moref_type=$(jq -r '.VirtualMachines[0].'"${type}"'.Type' <"${json}") || \
    fatal "failed to get VM's ${type}'s moref type"
  moref_value=$(jq -r '.VirtualMachines[0].'"${type}"'.Value' <"${json}") || \
    fatal "failed to get VM's ${type}'s moref value"
  moref="${moref_type}:${moref_value}"
  govc ls -L "${moref}" || \
    fatal "failed to get VM's ${type}'s inventory path"
}

get_moref_via_my_vm_2() {
  type="${1}"
  json="${2}"
  moref_type=$(jq -r '.VirtualMachines[0].'"${type}"'[0].Type' <"${json}") || \
    fatal "failed to get VM's ${type}'s moref type"
  moref_value=$(jq -r '.VirtualMachines[0].'"${type}"'[0].Value' <"${json}") || \
    fatal "failed to get VM's ${type}'s moref value"
  moref="${moref_type}:${moref_value}"
  govc ls -L "${moref}" || \
    fatal "failed to get VM's ${type}'s inventory path"
}

# Get all of the vSphere properties.
vsphere_server="$(rpc_get VSPHERE_SERVER)"
[ -n "${vsphere_server}" ] || exit 0
vsphere_server_port="$(rpc_get VSPHERE_SERVER_PORT)"
[ -n "${vsphere_server_port}" ] || vsphere_server_port=443
export GOVC_URL="${vsphere_server}:${vsphere_server_port}"

vsphere_server_insecure="$(rpc_get VSPHERE_SERVER_INSECURE)"
[ -n "${vsphere_server_insecure}" ] || vsphere_server_insecure=False
export GOVC_INSECURE="${vsphere_server_insecure}"

vsphere_username="$(rpc_get VSPHERE_USER)"
[ -n "${vsphere_username}" ] || exit 0
export GOVC_USERNAME="${vsphere_username}"

vsphere_password="$(rpc_get VSPHERE_PASSWORD)"
[ -n "${vsphere_password}" ] || exit 0
export GOVC_PASSWORD="${vsphere_password}"

# Get this VM's UUID.
self_uuid="$(get_self_uuid)" || fatal "failed to read VM UUID"

# Get this VM's information from the VI SDK.
self_json="$(mktemp)"
govc vm.info -vm.uuid "${self_uuid}" -json 1>"${self_json}" || \
  fatal "failed to get VM's info"

# Get the inventory path for this VM and the datacenter, datastore, 
# resource pool, folder, and the network to which this VM belongs.
GOVC_SELF="$(get_moref_via_my_vm Self "${self_json}")"
GOVC_DATACENTER="$(echo "${GOVC_SELF}" | awk -F/ '{print "/"$2}')"
export GOVC_DATACENTER
GOVC_DATASTORE="$(get_moref_via_my_vm_2 Datastore "${self_json}")"
export GOVC_DATASTORE
GOVC_RESOURCE_POOL="$(get_moref_via_my_vm ResourcePool "${self_json}")"
export GOVC_RESOURCE_POOL
GOVC_FOLDER="$(get_moref_via_my_vm Parent "${self_json}")"
export GOVC_FOLDER
GOVC_NETWORK="$(get_moref_via_my_vm_2 Network "${self_json}")"
export GOVC_NETWORK

# Remove the JSON file.
rm -f "${self_json}"

# Write all of the GOVC_ environment variables to GOVC_ENV.
{ echo "GOVC_SELF=\"${GOVC_SELF}\""; \
  echo "GOVC_URL=\"${GOVC_URL}\""; \
  echo "GOVC_INSECURE=\"${GOVC_INSECURE}\""; \
  echo "GOVC_USERNAME=\"${GOVC_USERNAME}\""; \
  echo "GOVC_PASSWORD=\"${GOVC_PASSWORD}\""; \
  echo "GOVC_DATACENTER=\"${GOVC_DATACENTER}\""; \
  echo "GOVC_DATASTORE=\"${GOVC_DATASTORE}\""; \
  echo "GOVC_RESOURCE_POOL=\"${GOVC_RESOURCE_POOL}\""; \
  echo "GOVC_FOLDER=\"${GOVC_FOLDER}\""; \
  echo "GOVC_NETWORK=\"${GOVC_NETWORK}\""; \
} >"${govc_env}"

# Determine if the vSphere cloud provider should be deployed.
cloud_provider_type="$(rpc_get CLOUD_PROVIDER_TYPE)"
if echo "${cloud_provider_type}" | grep -iq 'none'; then
  info "no cloud provider selected"
  exit 0
elif echo "${cloud_provider_type}" | grep -iq 'in-tree'; then
  info "configuring in-tree cloud provider"
  cloud_provider_type=in-tree
elif echo "${cloud_provider_type}" | grep -iq 'external'; then
  info "configuring external cloud provider"
  cloud_provider_type=external
else
  exit 0
fi

info "selected cloud provider: ${cloud_provider_type}"

vsphere_datacenter="$(basename "${GOVC_DATACENTER}")"
vsphere_datastore="$(basename "${GOVC_DATASTORE}")"
vsphere_resource_pool="$(basename "${GOVC_RESOURCE_POOL}")"
vsphere_folder="$(basename "${GOVC_FOLDER}")"
vsphere_network="$(basename "${GOVC_NETWORK}")"

# Update the insecure flag based on the expected value.
echo "${vsphere_server_insecure}" | grep -iq 'false' && \
  vsphere_server_insecure=0 || vsphere_server_insecure=1

if [ "${cloud_provider_type}" = "in-tree" ]; then
  cloud_provider=vsphere
  cloud_conf=$(cat <<EOF | gzip -9c | base64 -w0
[Global]
  user               = "${vsphere_username}"
  password           = "${vsphere_password}"
  port               = "${vsphere_server_port}"
  insecure-flag      = "${vsphere_server_insecure}"
  datacenters        = "${vsphere_datacenter}"

[VirtualCenter "${vsphere_server}"]

[Workspace]
  server             = "${vsphere_server}"
  datacenter         = "${vsphere_datacenter}"
  folder             = "${vsphere_folder}"
  default-datastore  = "${vsphere_datastore}"
  resourcepool-path  = "${vsphere_resource_pool}"

[Disk]
  scsicontrollertype = pvscsi

[Network]
  public-network     = "${vsphere_network}"
EOF
)
elif [ "${cloud_provider_type}" = "external" ]; then
  cloud_provider=external
  cloud_conf=$(cat <<EOF | gzip -9c | base64 -w0
[Global]
  secret-name        = "cloud-provider-vsphere-credentials"
  secret-namespace   = "kube-system"
  service-account    = "cloud-controller-manager"
  port               = "${vsphere_server_port}"
  insecure-flag      = "${vsphere_server_insecure}"
  datacenters        = "${vsphere_datacenter}"

[VirtualCenter "${vsphere_server}"]
EOF
)
  secrets_conf=$(cat <<EOF | gzip -9c | base64 -w0
apiVersion: v1
kind: Secret
metadata:
  name: cloud-provider-vsphere-credentials
  namespace: kube-system
data:
  ${vsphere_server}.username: "$(printf '%s' "${vsphere_username}" | base64 -w0)"
  ${vsphere_server}.password: "$(printf '%s' "${vsphere_password}" | base64 -w0)"
EOF
)
  rpc_set CLOUD_PROVIDER_EXTERNAL vsphere
  rpc_set MANIFEST_YAML_AFTER_RBAC_2 "${secrets_conf}"
fi

rpc_set CLOUD_PROVIDER "${cloud_provider}"
rpc_set CLOUD_CONFIG "${cloud_conf}"

exit 0
