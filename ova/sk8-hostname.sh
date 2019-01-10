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
# Used by the sk8 service to update the host's name.
#

# Load the sk8 commons library.
# shellcheck disable=SC1090
. "$(pwd)/sk8-common.sh"

# If this is the first node in the cluster the host FQDN must be
# figured out based on the cluster's shape.
if is_true "$(rpc_get BOOTSTRAP_CLUSTER)"; then
  # Get this VM's UUID.
  self_uuid="$(get_self_uuid)"

  # Generate a unique ID for the cluster.
  cluster_id=$(echo "${self_uuid}-$(date --utc '+%s')" | \
    sha1sum | awk '{print $1}')
  rpc_set CLUSTER_ID "${cluster_id}"
  info "cluster-id=${cluster_id}"

  # Get the short version of the cluster ID.
  cluster_id7="$(get_cluster_id7 "${cluster_id}")"

  # The domain name is generated using the first seven characters from the
  # cluster ID.
  domain_name="${cluster_id7}.sk8"
  rpc_set NETWORK_DOMAIN "${domain_name}"
  info "cluster-domain=${domain_name}"

  # The first node in the cluster is always a member of the control plane, so
  # the host name will always be c01.
  host_fqdn="c01.${domain_name}"

  rpc_set HOST_FQDN "${host_fqdn}"
else
  host_fqdn="$(rpc_get HOST_FQDN)"
fi

require host_fqdn

# Get the host name and domain name from the host's FQDN.
host_name="$(get_host_name_from_fqdn "${host_fqdn}")"
domain_name="$(get_domain_name_from_fqdn "${host_fqdn}")"

if ! set_host_name "${host_fqdn}" "${host_name}" "${domain_name}"; then
  case "${?}" in
  50)
      fatal "hostname -f returned empty string" 50
      ;;
  51)
      _act_host_fqdn="$(hostname -f)" || true
      fatal "exp_host_fqdn=${host_fqdn} act_host_fqdn=${_act_host_fqdn}" 51
      ;;
  52)
      fatal "hostname -s returned empty string" 52
      ;;
  53)
      _act_host_name="$(hostname -s)" || true
      fatal "exp_host_name=${host_name} act_host_name=${_act_host_name}" 53
      ;;
  54)
      fatal "hostname -d returned empty string" 54
      ;;
  55)
      _act_domain_name="$(hostname -d)" || true
      fatal "exp_domain_name=${domain_name} act_domain_name=${_act_domain_name}" 55
      ;;
  *)
      fatal "set_host_name failed" "${?}"
      ;;
  esac
fi

info "host name has been updated!"
info "    host fqdn  = ${host_fqdn}"
info "    host name  = ${host_name}"
info "  domain name  = ${domain_name}"

exit 0
