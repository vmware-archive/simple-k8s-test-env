#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

#
# Used by the yakity service to generate an SSH key if one is not present
# in yakity.SSH_PUB_KEY.
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

# Ensure the rpctool program is available.
command -v rpctool >/dev/null 2>&1 || fatal "failed to find rpctool command"

rpc_set() {
  rpctool set "yakity.${1}" "${2}" || fatal "rpctool: set yakity.${1} failed"
}

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

# Set up the SSH directory.
mkdir -p /root/.ssh; chmod 0700 /root/.ssh

# Check to see if there is an SSH public key to add to the root user's
# list of authorized keys, but do not allow the key to be added twice.
if val="$(get_config_val SSH_PUB_KEY)" && [ -n "${val}" ] && \
   { [ ! -f /root/.ssh/authorized_keys ] || \
       ! grep -qF "${val}" </root/.ssh/authorized_keys; }; then

  echo "updating /root/.ssh/authorized_keys"
  if [ -f /root/.ssh/authorized_keys ]; then
    echo >>/root/.ssh/authorized_keys
  fi
  chmod 0400 /root/.ssh/authorized_keys
  echo "${val}" >>/root/.ssh/authorized_keys
fi

# If there is no SSH key at all then generate one.
if [ ! -f /root/.ssh/id_rsa ]; then

  echo "generating a new SSH key pair"

  cluster_name="$(get_config_val CLUSTER_NAME)"
  cluster_name="${cluster_name:-kubernetes}"
  domain_name="$(hostname -d)"

  ssh-keygen \
    -b 2048 \
    -t rsa \
    -C "root@${cluster_name}.${domain_name}" \
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
