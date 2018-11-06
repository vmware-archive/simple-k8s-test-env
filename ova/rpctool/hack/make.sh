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

script_dir=$(python -c "import os; print(os.path.realpath('$(dirname "${0}")'))")
parent_dir="${script_dir}/.."

# Download dep
if [ ! -f 'dep' ]; then
  docker run -it \
    --rm \
    -v "${parent_dir}":/go/src/rpctool \
    golang:1.11.1 \
    /bin/sh -c 'cd /go/src/rpctool && { [ -f dep ] || curl -Lo dep https://github.com/golang/dep/releases/download/v0.5.0/dep-linux-amd64 && chmod 0755 dep; }'
fi

# Build rpctool
docker run -it \
  --rm \
  -v "${parent_dir}":/go/src/rpctool \
  golang:1.11.1 \
  make -C /go/src/rpctool
