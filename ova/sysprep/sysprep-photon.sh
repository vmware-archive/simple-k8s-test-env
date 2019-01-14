#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

# Load the sk8 commons library.
# shellcheck disable=SC1090
. "$(pwd)/sk8-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0

is_true "$(rpc_get SYSPREP)" || exit 0
touch "${_done_file}"

printf '' >/etc/machine-id && \
rm -fr /var/lib/cloud/instances && \
rm -rf /etc/ssh/*key* && \
rm -fr /var/log && mkdir -p /var/log && \
echo 'clearing history & sealing the VM...' && \
unset HISTFILE && history -c && rm -fr /root/.bash_history && \
shutdown -P now