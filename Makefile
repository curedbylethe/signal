# signal developer tasks. Run `make help` for the list.

SALAM ?= salam
BUILD := build
FLAGS := --log-level=warn --backend=llvm
SOURCES := signal.salam tests ci

# Salam links with the host toolchain on macOS. Pin the deployment target to
# the running OS so the linker does not warn about mismatched SDK versions.
ifeq ($(shell uname -s),Darwin)
export MACOSX_DEPLOYMENT_TARGET ?= $(shell sw_vers -productVersion)
endif

.PHONY: help build test test-llvm format check check-abi clean

help:
	@echo "make build     compile a consumer of signal.salam with --backend=llvm"
	@echo "make test      build and run the test suite (tests/run.sh)"
	@echo "make test-llvm build and run the test suite with --backend=llvm"
	@echo "make format    format all Salam sources in place"
	@echo "make check     format check, ABI oracle, build and tests (the library gate; CI also runs test-llvm)"
	@echo "make check-abi compile and run the sigaction layout oracle against this host"
	@echo "make clean     remove build output"

build:
	@mkdir -p $(BUILD)
	@printf 'include "../signal.salam"\n\nfunc main:\n    println signal.WinchSupported()\nend\n' > $(BUILD)/check.salam
	$(SALAM) build $(BUILD)/check.salam --output=$(BUILD)/check $(FLAGS)

test:
	SALAM=$(SALAM) sh tests/run.sh

test-llvm:
	SALAM=$(SALAM) SALAM_BACKEND=llvm sh tests/run.sh

format:
	$(SALAM) format $(SOURCES)

check:
	$(SALAM) format --check $(SOURCES)
	$(MAKE) check-abi
	$(MAKE) build test

check-abi:
	@mkdir -p $(BUILD)
	cc -std=c11 -Wall -Wextra -o $(BUILD)/sigaction_offsets ci/sigaction_offsets.c
	$(BUILD)/sigaction_offsets

clean:
	rm -rf $(BUILD) .salam-build
