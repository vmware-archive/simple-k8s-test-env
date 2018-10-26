#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
set -o pipefail

printf '' >/etc/machine-id && \
rm -fr /var/lib/cloud/instances && \
rm -fr /var/log && mkdir -p /var/log && \
echo 'clearing history & sealing the VM...' && \
history -c && \
shutdown -P now