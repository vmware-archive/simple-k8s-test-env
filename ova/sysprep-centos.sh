#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

set -e
set -o pipefail

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
rm -f /etc/ssh/*key* && \
rm -f /root/.bash_history && \
unset HISTFILE && \
rm -rf /root/.ssh/ && \
rm -f /root/anaconda-ks.cfg && \
rm -rf /var/log/* && \
echo 'clearing history & sealing the VM...' && \
history -c && \
sys-unconfig
