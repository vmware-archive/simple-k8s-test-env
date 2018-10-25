#!/bin/sh

# The below commands are what are used to prep a vanilla PhotonOS2
# installation in preparation to be processed by the yakity prep
# scripts.
tdnf upgrade -y && \
tdnf install -y ipvsadm unzip && \
{ cat >/etc/sysconfig/iptables <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

# Block all null packets.
-A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# Reject a syn-flood attack.
-A INPUT -p tcp ! --syn -m state --state NEW -j DROP

# Block XMAS/recon packets.
-A INPUT -p tcp --tcp-flags ALL ALL -j DROP

# Allow all incoming packets on the loopback interface.
-A INPUT -i lo -j ACCEPT

# Allow SSH on all interfaces.
-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT

# Allow incoming packets for established connections.
-I INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow all outgoing packets.
-P OUTPUT ACCEPT

# Drop everything else.
-P INPUT DROP

# Enable the rules.
COMMIT
EOF
} && \
rm -f /etc/sysconfig/ip6tables && \
cp /etc/sysconfig/iptables /etc/sysconfig/ip6tables && \
ln -s /usr/bin/python3 /usr/bin/python && \
mkdir -p /opt/bin && chmod 0755 /opt /opt/bin && cd /opt/bin && \
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip" && \
unzip awscli-bundle.zip && \
awscli-bundle/install -i /opt/aws -b /opt/bin/aws && \
/bin/rm -fr awscli-bundle awscli-bundle.zip && \
curl -sSLo jq https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 && \
chmod 0755 jq