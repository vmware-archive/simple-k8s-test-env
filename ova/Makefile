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

all: build

LINUX_DISTRO ?= photon
OVF_EXPORT_DIR ?= $(HOME)/Downloads

govc: govc-linux-amd64
govc-linux-amd64:
	go get github.com/vmware/govmomi/govc
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
	go build -a -tags netgo -ldflags "-w" \
	-o $@ github.com/vmware/govmomi/govc

turn-up-$(LINUX_DISTRO): prep-$(LINUX_DISTRO)
prep-$(LINUX_DISTRO): govc-linux-amd64
	LINUX_DISTRO=$(LINUX_DISTRO) hack/prep.sh

seal-$(LINUX_DISTRO): govc-linux-amd64
	LINUX_DISTRO=$(LINUX_DISTRO) hack/prep.sh seal

turn-down-$(LINUX_DISTRO):
	LINUX_DISTRO=$(LINUX_DISTRO) hack/turn-down.sh

prep turn-up: prep-$(LINUX_DISTRO)
seal: seal-$(LINUX_DISTRO)
turn-up: prep-$(LINUX_DISTRO)
turn-down: turn-down-$(LINUX_DISTRO)

%-1.vmdk: $(OVF_EXPORT_DIR)/%-1.vmdk
	cp -f $? $@

yakity-%.ovf: ovf/%.ovf ovf/product-section.ovf
	@rm -f $@
	cat $^ >>$@
	printf '\n  </VirtualSystem>\n</Envelope>' >> $@

yakity-%.ova:	yakity-%.ovf yakity-%-1.vmdk
	@rm -f $@
	tar -cf $@ $^

ova: build
build: yakity-$(LINUX_DISTRO).ova

upload: upload-$(LINUX_DISTRO)

upload-%: yakity-%.ova
	aws s3 cp $< s3://cnx.vmware/cicd/$< \
	  --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers && \
	  echo https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/$<

.PHONY: prep seal turn-up turn-down upload

.PRECIOUS: %-1.vmdk yakity-%.ovf
