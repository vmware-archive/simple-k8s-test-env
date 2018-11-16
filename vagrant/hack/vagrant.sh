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
# A wrapper for vagrant that chooses its data directory from the input flags.
#

export PROGRAM="vagrant"

# Load the commons library.
# shellcheck disable=SC1090
. "$(dirname "${0}")/common.sh"

case "${1}" in
up)
  print_context
  # shellcheck disable=SC1004
  exec /bin/sh -c 'vagrant up --provision-with init-guest && \
    vagrant provision --provision-with file,init-yakity && \
    vagrant provision --provision-with start-yakity'
  ;;
vup)
  print_context
  exec vagrant up "${@}"
  ;;
down)
  print_context
  exec vagrant destroy -f
  ;;
*)
  exec vagrant "${@}"
  ;;
esac
