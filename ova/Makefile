all: build

LINUX_DISTRO ?= photon
OVF_EXPORT_DIR ?= $(HOME)/Downloads

govc: govc-linux-amd64
govc-linux-amd64:
	go get github.com/vmware/govmomi/govc
	GOOS=linux GOARCH=amd64 CGO_ENABLED=0 \
	go build -a -tags netgo -ldflags "-w" \
	-o $@ github.com/vmware/govmomi/govc

prep-centos prep-photon: govc-linux-amd64
	LINUX_DISTRO=$(subst prep-,,$@) hack/prep.sh

seal-centos seal-photon: govc-linux-amd64
	LINUX_DISTRO=$(subst seal-,,$@) hack/prep.sh seal

prep: prep-$(LINUX_DISTRO)

seal: seal-$(LINUX_DISTRO)

%-1.vmdk: $(OVF_EXPORT_DIR)/%-1.vmdk
	cp -f $? $@

%-2.nvram: $(OVF_EXPORT_DIR)/%-2.nvram
	cp -f $? $@

yakity-%.ova: yakity-%.ovf yakity-%-1.vmdk yakity-%-2.nvram
	tar -cf $@ $^

build ova: yakity-centos.ova yakity-photon.ova

upload-centos: yakity-centos.ova
	aws s3 cp $< s3://cnx.vmware/cicd/$< \
	  --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers && \
	  echo https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/$<

upload-photon: yakity-photon.ova
	aws s3 cp $< s3://cnx.vmware/cicd/$< \
	  --grants read=uri=http://acs.amazonaws.com/groups/global/AllUsers && \
	  echo https://s3-us-west-2.amazonaws.com/cnx.vmware/cicd/$<

.PHONY: prep seal upload \
		prep-centos seal-centos upload-centos \
		prep-photon seal-photon upload-photon

.PRECIOUS: %-1.vmdk %-2.nvram
