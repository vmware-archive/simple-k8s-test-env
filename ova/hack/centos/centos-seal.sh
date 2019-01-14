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

yum install -y https://github.com/akutz/cloud-init-vmware-guestinfo/releases/download/v1.1.0/cloud-init-vmware-guestinfo-1.1.0-1.el7.noarch.rpm \
               cloud-utils-growpart && \
service rsyslog stop && \
service auditd stop && \
package-cleanup -y --oldkernels --count=1 && \
yum clean -y all && \
logrotate -f /etc/logrotate.conf && \
printf '' >/etc/machine-id && \
rm -fr /var/lib/cloud/instances && \
rm -f /var/log/*-???????? /var/log/*.gz && \
rm -f /var/log/dmesg.old && \
rm -rf /var/log/anaconda && \
cat /dev/null > /var/log/audit/audit.log && \
cat /dev/null > /var/log/wtmp && \
cat /dev/null > /var/log/lastlog && \
cat /dev/null > /var/log/grubby && \
rm -f /etc/udev/rules.d/70* && \
sed -i '/^(HWADDR|UUID)=/d' /etc/sysconfig/network-scripts/ifcfg-e* && \
rm -rf /tmp/* && \
rm -rf /var/tmp/* && \
rm -rf /etc/ssh/*key* /root/.ssh && \
rm -f /root/anaconda-ks.cfg && \
rm -rf /var/log && mkdir -p /var/log && \
echo 'clearing history & sealing the VM...' && \
unset HISTFILE && history -c && rm -fr /root/.bash_history && \
sys-unconfig
