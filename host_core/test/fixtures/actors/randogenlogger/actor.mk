# common makefile rules for building actors
#
# Before including this, your project Makefile should define the following:
#
# Required
# -----------
# PROJECT      - Short name for the project, must be valid filename chars, no spaces
# CLAIMS       - Space-separated list of capability contracts to use for signing
#                These should match the capability providers the actor needs to use.
#                For example: 
#                    wasmcloud:httpserver wasmcloud:builtin:logging
# VERSION      - The actor version number, usually semver format, X.Y.Z
# REVISION     - A number that should be incremented with every build,
#                whether or not VERSION has changed
# REG_URL      - Registry url, e.g. 'localhost:5000' or 'wasmcloud.azurecr.io'
# PUSH_REG_CMD - Command to push to registry, for example:
#                    wash reg push --insecure $(REG_URL)
#
# 
# Optional
# -----------
# KEYDIR    - path to private key folder
# CARGO     - cargo binary (name or path), defaults to cargo
# WASH      - wash binary (name or path), defaults to wash
# DIST_WASM - the final file after building and signing
# TARGET_DIR - location of cargo build target folder if not in current dir
#              (if it's in a workspace, it may be elsewhere)
# WASM_TARGET - type of wasm file, defaults to wasm32-unknown-unknown
#

KEYDIR    ?= .keys
CARGO     ?= cargo
WASH      ?= wash
# location of cargo output files
TARGET_DIR ?= target
# location of wasm file after build and signing
DIST_WASM ?= build/$(PROJECT)_s.wasm
WASM_TARGET ?= wasm32-unknown-unknown
ACTOR_NAME  ?= $(PROJECT)
UNSIGNED_WASM = $(TARGET_DIR)/$(WASM_TARGET)/release/$(PROJECT).wasm

# verify all required variables are set
check-var-defined = $(if $(strip $($1)),,$(error Required variable "$1" is not defined))

$(call check-var-defined,PROJECT)
$(call check-var-defined,CLAIMS)
$(call check-var-defined,VERSION)
$(call check-var-defined,REVISION)
$(call check-var-defined,REG_URL)
$(call check-var-defined,PUSH_REG_CMD)

all:: $(DIST_WASM)

# default target is signed wasm file
# sign it
$(DIST_WASM): $(UNSIGNED_WASM) Makefile
	@mkdir -p $(dir $@)
	$(WASH) claims sign $< \
		$(foreach claim,$(CLAIMS), -c $(claim) ) \
		--name $(ACTOR_NAME) --ver $(VERSION) --rev $(REVISION) \
		$(if $(ACTOR_ALIAS),--call-alias $(ACTOR_ALIAS)) \
		--destination $@

# rules to print file name and path of build target
target-path:
	@echo $(DIST_WASM)
target-path-abs:
	@echo $(abspath $(DIST_WASM))
target-file:
	@echo $(notdir $(DIST_WASM))

# the wasm should be rebuilt if any source files or dependencies change
$(UNSIGNED_WASM): .FORCE
	$(CARGO) build --release

# push signed wasm file to registry
push: $(DIST_WASM)
	$(PUSH_REG_CMD) $(DIST_WASM)

# tell host to start an instance of the actor
start:
	$(WASH) ctl start actor $(REG_URL) --timeout-ms 3000

# NOT WORKING - live actor updates not working yet
# update it (should update revision before doing this)
#update:
#	$(PUSH_REG_CMD) $(DIST_WASM)
#	$(WASH) ctl update actor  \
#        $(shell $(WASH) ctl get hosts -o json | jq -r ".hosts[0].id") \
#	    $(shell make --silent actor_id) \
#	    $(REG_URL) --timeout-ms 3000

inventory:
	$(WASH) ctl get inventory $(shell $(WASH) ctl get hosts -o json | jq -r ".hosts[0].id")

ifneq ($(wildcard test-options.json),)
# if this is a test actor, run its start method
# project makefile can set RPC_TEST_TIMEOUT_MS to override default
RPC_TEST_TIMEOUT_MS ?= 2000
test::
	$(WASH) call --test --data test-options.json --rpc-timeout-ms $(RPC_TEST_TIMEOUT_MS) \
	    $(shell make --silent actor_id) \
	    Start
endif

# generate release build
release::
	cargo build --release

# standard rust commands
check clippy doc:
	$(CARGO) $@

# remove 
clean::
	$(CARGO) clean
	rm -rf build

inspect claims: $(DIST_WASM)
	$(WASH) claims inspect $(DIST_WASM)

# need a signed wasm before we can print the id
_actor_id: $(DIST_WASM)
	@$(WASH) claims inspect $(DIST_WASM) -o json | jq -r .module

actor_id:
	@echo $(shell make --silent _actor_id 2>/dev/null | tail -1)

ifeq ($(wildcard codegen.toml),codegen.toml)
# if there are interfaces here, enable lint and validate rules
lint validate::
	$(WASH) $@
else
lint validate::

endif

.PHONY: actor_id check clean clippy doc release test update .FORCE
