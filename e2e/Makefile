all: build

E2E_IMAGE := gcr.io/kubernetes-conformance-testing/yake2e:latest
E2E_JOB_IMAGE := gcr.io/kubernetes-conformance-testing/yake2e-job:latest

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
					upload_e2e.py
	$(DOCKER_BUILD) $(E2E_IMAGE) . && touch "$@"

.Dockerfile.job.built: 	Dockerfile.job \
						e2e-job.sh \
						$(KEEPALIVE)
	$(DOCKER_BUILD) $(E2E_JOB_IMAGE) -f "$<" . && touch "$@"

build: .Dockerfile.built .Dockerfile.job.built

.Dockerfile.pushed: .Dockerfile.built
	docker push $(E2E_IMAGE) && touch "$@"

.Dockerfile.job.pushed: .Dockerfile.job.built
	docker push $(E2E_JOB_IMAGE) && touch "$@"

push: .Dockerfile.pushed .Dockerfile.job.pushed

.PHONY: build push
