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

printf 'changeme\nchangeme' | passwd && \
printf '' >/etc/machine-id && \
rm -fr /var/lib/cloud/instances && \
rm -rf /etc/ssh/*key* /root/.ssh && \
rm -fr /var/log && mkdir -p /var/log && \
echo 'clearing history & sealing the VM...' && \
unset HISTFILE && history -c && rm -fr /root/.bash_history