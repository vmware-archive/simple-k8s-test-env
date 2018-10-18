all: build

YAKITY_CENTOS_VMDK ?= $(HOME)/Downloads/yakity-centos-1.vmdk
YAKITY_CENTOS_NVRAM ?= $(HOME)/Downloads/yakity-centos-2.nvram

prep-centos:
	LINUX_DISTRO=centos hack/prep.sh

seal-centos:
	LINUX_DISTRO=centos hack/prep.sh seal

yakity-centos-1.vmdk: $(YAKITY_CENTOS_VMDK)
	cp -f $? $@

yakity-centos-2.nvram: $(YAKITY_CENTOS_NVRAM)
	cp -f $? $@

yakity-centos.ova: yakity-centos.ovf yakity-centos-1.vmdk yakity-centos-2.nvram
	tar -cf $@ $^

prep: prep-centos

seal: seal-centos

upload: yakity-centos.ova
	$(foreach f,$^,aws s3 cp $(f) s3://cnx.vmware/cicd/$(notdir $(f)) --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers && echo https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/$(notdir $(f)))

build: yakity-centos.ova

.PHONY: prep-centos seal-centos prep seal upload
