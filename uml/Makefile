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

PUML:=$(wildcard *.puml)
SVGS:=$(patsubst %.puml,%.svg,$(PUML))

%.svg: %.puml
	plantuml -tsvg $?

build: $(SVGS)

upload: $(SVGS)
	aws s3 cp . s3://cnx.vmware/cicd/sk8/svg/ \
	  --recursive --exclude "*" \
	  $(foreach f,$(SVGS),--include "$(f)") \
	  --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers

.PHONY: upload
