all: build

E2E_IMAGE := gcr.io/kubernetes-conformance-testing/sk8e2e:latest

DOCKER_BUILD := docker build
ifeq (true,$(NOCACHE))
DOCKER_BUILD += --no-cache
endif
DOCKER_BUILD += -t

KEEPALIVE := hack/keepalive/keepalive.linux_amd64
$(KEEPALIVE):
	$(MAKE) -C hack/keepalive keepalive.linux_amd64

.Dockerfile.built: 	Dockerfile \
					*.tf vmc/*.tf \
					cloud_config.yaml \
					entrypoint.sh \
					sonobuoy.yaml \
					upload_e2e.py \
					$(KEEPALIVE)
	$(DOCKER_BUILD) $(E2E_IMAGE) . && touch "$@"

build: .Dockerfile.built

.Dockerfile.pushed: .Dockerfile.built
	docker push $(E2E_IMAGE) && touch "$@"


push: .Dockerfile.pushed

.PHONY: build push
