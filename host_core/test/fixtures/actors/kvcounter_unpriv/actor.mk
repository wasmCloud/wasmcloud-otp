# common makefile rules for building actors
#
# Before including this, your project Makefile should define the following:
#
# Required
# -----------
# PROJECT      - Short name for the project, must be valid filename chars, no spaces
# CLAIMS       - Space-separtaed list of capability contracts to use for signing
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
# RUST_DEPS - rust source files
# DIST_WASM - the final file after building and signing
# TARGET_DIR - location of cargo build target folder if not in current dir
#              (if it's in a workspace, it may be elsewhere)
# WASM_TARGET - type of wasm file, defaults to wasm32-unknown-unknown
#

KEYDIR    ?= .keys
CARGO     ?= cargo
WASH      ?= wash
RUST_DEPS ?= Cargo.toml Makefile $(wildcard src/*.rs) .cargo/config.toml
# location of cargo output files
TARGET_DIR ?= target
# location of wasm file after build and signing
DIST_WASM ?= build/$(PROJECT)_s.wasm
WASM_TARGET ?= wasm32-unknown-unknown
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
	@WASH_ISSUER_KEY=$(shell cat .keys/account.nk) \
	WASH_SUBJECT_KEY=$(shell cat .keys/module.nk) \
	$(WASH) claims sign $< \
		$(foreach claim,$(CLAIMS), -c $(claim) ) \
		--name "$(PROJECT)" --ver $(VERSION) --rev $(REVISION) \
		--destination $@
	mv $@ ../kvcounter_unpriv_s.wasm


# the wasm should be rebuilt if any source files change
$(UNSIGNED_WASM): $(RUST_DEPS)
	$(CARGO) build --release


# push signed wasm file to registry
push: $(DIST_WASM)
	$(PUSH_REG_CMD) $(DIST_WASM)

# tell host to start an instance of the actor
start:
	$(WASH) ctl start actor $(REG_URL) --timeout 3

# NOT WORKING - live actor updates not working yet
# update it (should update revision before doing this)
#update:
#	$(PUSH_REG_CMD) $(DIST_WASM)
#	$(WASH) ctl update actor  \
#        $(shell $(WASH) ctl get hosts -o json | jq -r ".hosts[0].id") \
#	    $(shell make actor_id) \
#	    $(REG_URL) --timeout 3

inventory:
	$(WASH) ctl get inventory $(shell $(WASH) ctl get hosts -o json | jq -r ".hosts[0].id")

ifneq ($(wildcard test-options.json),)
# if this is a test actor, run its start method
# project makefile can set RPC_TEST_TIMEOUT to override default
RPC_TEST_TIMEOUT ?= 2
test::
	$(WASH) call --test --data test-options.json --rpc-timeout $(TEST_TIMEOUT) \
	    $(shell make actor_id) \
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
	@echo $(shell make _actor_id 2>/dev/null | tail -1)

ifeq ($(wildcard codegen.toml),codegen.toml)
# if there are interfaces here, enable lint and validate rules
lint validate::
	$(WASH) $@
else
lint validate::

endif

.PHONY: actor_id check clean clippy doc release test update
