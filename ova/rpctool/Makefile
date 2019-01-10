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

all: build

vendor: | dep
	./dep ensure -v

Gopkg.lock: main.go Gopkg.toml | dep
	./dep ensure -v

Gopkg.toml: | dep
	./dep init -v

rpctool: main.go Gopkg.lock | vendor
	CGO_ENABLED=0 go build -a -tags netgo -ldflags "-w" -o "$@"

build: rpctool

clean:
	rm -fr dep rpctool

.PHONY: clean
