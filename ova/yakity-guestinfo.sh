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
# Used by the yakity service to write the yakity environment
# file by reading properties from the VMware GuestInfo interface.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0
touch "${_done_file}"

YAK_DEFAULTS="${YAK_DEFAULTS:-/etc/default/yakity}"

write_config_val() {
  if [ -n "${2}" ]; then
    printf '%s="%s"\n' "${1}" "${2}" >>"${YAK_DEFAULTS}"
    printf 'set config val\n  key = %s\n' "${1}" 1>&2
  elif val="$(rpc_get "${1}")" && [ -n "${val}" ]; then
    printf '%s="%s"\n' "${1}" "${val}" >>"${YAK_DEFAULTS}"
    printf 'set config val\n  key = %s\n' "${1}" 1>&2
  fi
}

# Write the following config keys to the config file.
write_config_val NODE_TYPE
write_config_val ETCD_DISCOVERY

# Iterate over the common config keys to write to the config file.
while IFS= read -r key; do
  write_config_val "${key}"
done <yakity-config-keys.env

exit 0
