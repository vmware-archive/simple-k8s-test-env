#!/bin/sh

# posix compliant
# verified by https://www.shellcheck.net

# Load the yakity commons library.
# shellcheck disable=SC1090
. "$(pwd)/yakity-common.sh"

_done_file="$(pwd)/.$(basename "${0}").done"
[ ! -f "${_done_file}" ] || exit 0

is_true "$(rpc_get SYSPREP)" || exit 0
touch "${_done_file}"

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
rm -rf /etc/ssh/*key* && \
rm -f /root/anaconda-ks.cfg && \
rm -rf /var/log && mkdir -p /var/log && \
echo 'clearing history & sealing the VM...' && \
unset HISTFILE && history -c && rm -fr /root/.bash_history && \
sys-unconfig
