#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to write the yakity environment
# file by reading properties from the VMware GuestInfo interface.
#

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

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

# Get the PEM-encoded CA.
if val="$(rpc_get TLS_CA_PEM)" && [ -n "${val}" ]; then
  pem="$(mktemp)"
  echo "${val}" | \
    sed -r 's/(-{5}BEGIN [A-Z ]+-{5})/&\n/g; s/(-{5}END [A-Z ]+-{5})/\n&\n/g' | \
    sed -r 's/.{64}/&\n/g; /^\s*$/d' | \
    sed -r '/^$/d' >"${pem}"
  ca_crt_gz="$(openssl x509 2>/dev/null <"${pem}" | gzip -9c | base64 -w0)"
  write_config_val TLS_CA_CRT_GZ "${ca_crt_gz}"
  ca_key_gz="$(openssl rsa 2>/dev/null <"${pem}" | gzip -9c | base64 -w0)"
  write_config_val TLS_CA_KEY_GZ "${ca_key_gz}"
  rm -f "${pem}"
fi

# Write the following config keys to the config file.
write_config_val NODE_TYPE
write_config_val ETCD_DISCOVERY

# Iterate over the common config keys to write to the config file.
while IFS= read -r key; do
  write_config_val "${key}"
done <yakity-config-keys.env

exit 0
