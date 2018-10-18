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
