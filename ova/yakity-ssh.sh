#!/bin/sh

# Yakity
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
# Used by the yakity service to generate an SSH key if one is not present
# in yakity.SSH_PUB_KEY.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0
touch "${_done_file}"

# Set up the SSH directory.
mkdir -p /root/.ssh; chmod 0700 /root/.ssh

# Check to see if there is an SSH public key to add to the root user's
# list of authorized keys, but do not allow the key to be added twice.
if val="$(rpc_get SSH_PUB_KEY)" && [ -n "${val}" ] && \
   { [ ! -f /root/.ssh/authorized_keys ] || \
       ! grep -qF "${val}" </root/.ssh/authorized_keys; }; then

  info "updating /root/.ssh/authorized_keys"
  if [ -f /root/.ssh/authorized_keys ]; then
    echo >>/root/.ssh/authorized_keys
  fi
  chmod 0400 /root/.ssh/authorized_keys
  echo "${val}" >>/root/.ssh/authorized_keys
fi

# If there is no SSH key at all then generate one.
if [ ! -f /root/.ssh/id_rsa ]; then
  info "generating a new SSH key pair"

  cluster_name="$(rpc_get CLUSTER_NAME)"
  cluster_name="${cluster_name:-kubernetes}"
  domain_name="$(rpc_get NETWORK_DOMAIN)"
  domain_name="${domain_name:-$(hostname -d)}"
  cluster_fqdn="${cluster_name}.${domain_name}"

  ssh-keygen \
    -b 2048 \
    -t rsa \
    -C "root@${cluster_fqdn}" \
    -N "" \
    -f /root/.ssh/id_rsa

  chmod 0400 /root/.ssh/id_rsa
  chmod 0400 /root/.ssh/id_rsa.pub

  if [ -f /root/.ssh/authorized_keys ]; then
    echo >>/root/.ssh/authorized_keys
  fi
  cat /root/.ssh/id_rsa.pub >>/root/.ssh/authorized_keys
  chmod 0400 /root/.ssh/authorized_keys
fi

rpc_set SSH_PRV_KEY - </root/.ssh/id_rsa
rpc_set SSH_PUB_KEY - </root/.ssh/id_rsa.pub

exit 0
