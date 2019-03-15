all: build

IMAGE := gcr.io/kubernetes-conformance-testing/sk8e2e
TAG ?= $(shell git describe --always --dirty)
KEEPALIVE := hack/keepalive/keepalive.linux_amd64

$(KEEPALIVE):
	$(MAKE) -C hack/keepalive keepalive.linux_amd64

build: image
image: $(KEEPALIVE)
	docker build -t "$(IMAGE):$(TAG)" .
	docker tag "$(IMAGE):$(TAG)" "$(IMAGE):latest"

push: image
	docker push "$(IMAGE):$(TAG)"
	docker push "$(IMAGE):latest"

.PHONY: build image push
