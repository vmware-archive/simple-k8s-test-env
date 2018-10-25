#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to write the yakity environment
# file by reading properties from the VMware GuestInfo interface.
#

set -e
set -o pipefail

# Add ${BIN_DIR} to the path
BIN_DIR="${BIN_DIR:-/opt/bin}"; mkdir -p "${BIN_DIR}"; chmod 0755 "${BIN_DIR}"
echo "${PATH}" | grep -qF "${BIN_DIR}" || export PATH="${BIN_DIR}:${PATH}"

# echo2 echoes the provided arguments to file descriptor 2, stderr.
echo2() { echo "${@}" 1>&2; }

# fatal echoes a string to stderr and then exits the program.
fatal() { exit_code="${2:-${?}}"; echo2 "${1}"; exit "${exit_code}"; }

if ! command -v rpctool >/dev/null 2>&1; then
  fatal "failed to find rpctool command"
fi

YAK_DEFAULTS="${YAK_DEFAULTS:-/etc/default/yakity}"

get_config_val() {
  val="$(rpctool get "yakity.${1}")" || fatal "rpctool: get yakity.${1} failed"
  if [ -n "${val}" ]; then
    printf 'got config val\n  key = %s\n  src = %s\n' \
      "${1}" "guestinfo.yakity" 1>&2
    echo "${val}"
  else
    val="$(rpctool get.ovf "${1}")" || fatal "rpctool: get.ovf ${1} failed"
    if [ -n "${val}" ]; then
      printf 'got config val\n  key = %s\n  src = %s\n' \
        "${1}" "guestinfo.ovfEnv" 1>&2
      echo "${val}"
    fi
  fi
}

write_config_val() {
  if [ -n "${2}" ]; then
    printf '%s="%s"\n' "${1}" "${2}" >>"${YAK_DEFAULTS}"
    printf 'set config val\n  key = %s\n' "${1}" 1>&2
  elif val="$(get_config_val "${1}")" && [ -n "${val}" ]; then
    printf '%s="%s"\n' "${1}" "${val}" >>"${YAK_DEFAULTS}"
    printf 'set config val\n  key = %s\n' "${1}" 1>&2
  fi
}

# Check to see if there is an SSH public key to add to the root user.
if val="$(get_config_val SSH_PUB_KEY)" && [ -n "${val}" ]; then
  mkdir -p /root/.ssh; chmod 0700 /root/.ssh
  echo >>/root/.ssh/authorized_keys; chmod 0400 /root/.ssh/authorized_keys
  echo "${val}" >>/root/.ssh/authorized_keys
  echo2 "updated /root/.ssh/authorized_keys"
fi

# Get the PEM-encoded CA.
if val="$(get_config_val TLS_CA_PEM)" && [ -n "${val}" ]; then
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
