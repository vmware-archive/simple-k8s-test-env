all: build

build: keepalive keepalive.linux_amd64

keepalive: keepalive.go
	CGO_ENABLED=0 \
	  go build -a -tags netgo -ldflags '-w' -o "$@" "$<"

keepalive.linux_amd64: keepalive.go
	CGO_ENABLED=0 \
	  GOOS=linux \
	  GOARCH=amd64 \
	  go build -a -tags netgo -ldflags '-w' -o "$@" "$<"

test: keepalive
	./"$<" \
	  -quiet-tolerance 5s \
	  -sleep-for 1s \
	  -- \
	  $$(pwd)/periodic_writes.sh Do some periodic writes

clean:
	rm -f keepalive keepalive.linux_amd64

.PHONY: test clean
	