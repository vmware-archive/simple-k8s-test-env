#!/bin/sh

printf '' >/etc/machine-id && \
printf 'changeme\nchangeme' | passwd && \
rm -f /root/yakity.sh && \
rm -fr /var/lib/cloud/instances && \
rm -fr /root/.ssh/authorized_keys 
rm -fr /var/log && mkdir -p /var/log
