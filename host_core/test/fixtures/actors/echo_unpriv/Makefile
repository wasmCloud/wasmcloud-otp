# examples/actor/echo

PROJECT  = echo_unpriv
VERSION  = $(shell cargo metadata --no-deps --format-version 1 | jq -r '.packages[] .version' | head -1)
REVISION = 4
# list of all contract claims for actor signing (space-separated)
CLAIMS   = "wasmcloud:httpserver"
# registry url for our actor
REG_URL  = localhost:5000/v2/$(PROJECT):$(VERSION)
# command to upload to registry (without last wasm parameter)
PUSH_REG_CMD = wash reg push --insecure $(REG_URL)

include actor.mk

