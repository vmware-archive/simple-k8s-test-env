#!/bin/sh

printf 'changeme\nchangeme' | passwd && \
rm -fr /root/.ssh/authorized_keys && \
printf '' >/etc/machine-id && \
rm -fr /var/lib/cloud/instances && \
rm -fr /var/log && mkdir -p /var/log && \
echo 'clearing history & sealing the VM...' && \
unset HISTFILE && history -c && rm -fr /root/.bash_history