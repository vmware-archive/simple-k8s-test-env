all: build

IMAGE := gcr.io/kubernetes-conformance-testing/sk8e2e:latest
KEEPALIVE := hack/keepalive/keepalive.linux_amd64

$(KEEPALIVE):
	$(MAKE) -C hack/keepalive keepalive.linux_amd64

build: image
image: $(KEEPALIVE)
	docker build -t $(IMAGE) .

push: image
	docker push $(IMAGE)

.PHONY: build image push
