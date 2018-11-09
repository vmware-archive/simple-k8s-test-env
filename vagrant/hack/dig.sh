#!/bin/sh

# Yakity
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

# posix compliant
# verified by https://www.shellcheck.net

#
# A wrapper for dig that queries the first node in the cluster.
#

export PROGRAM="dig"

# Load the commons library.
# shellcheck disable=SC1090
. "$(dirname "${0}")/common.sh"

dns_port="$(cat "${DNSCONFIG}")"
exec dig +domain=yakity -4 +tcp @127.0.0.1 -p "${dns_port}" "${@}"
