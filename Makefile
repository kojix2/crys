SHELL := /bin/sh
.DEFAULT_GOAL := build

BINARY := crys
BIN_DIR := bin
BIN_PATH := $(BIN_DIR)/$(BINARY)
PREFIX ?= $(HOME)/.local
INSTALL_DIR ?= $(PREFIX)/bin

release ?= 0
parallel ?= 0

SHARDS_BUILD_FLAGS :=
CRYSTAL_DEFINE_FLAGS :=

ifeq ($(release),1)
SHARDS_BUILD_FLAGS += --release
endif

ifeq ($(parallel),1)
CRYSTAL_DEFINE_FLAGS += -Dpreview_mt -Dexecution_context
endif

.PHONY: help build test test-unit test-integration install uninstall clean

help:
	@echo "Available targets:"
	@echo "  build            Build $(BIN_PATH) (default target; release=1 parallel=1 supported)"
	@echo "  test             Run unit + integration tests"
	@echo "  test-unit        Run unit tests"
	@echo "  test-integration Run integration tests"
	@echo "  install          Install current build, or build first if missing"
	@echo "  uninstall        Remove installed binary"
	@echo "  clean            Remove built binary"
	@echo ""
	@echo "Examples:"
	@echo "  make"
	@echo "  make release=1"
	@echo "  make parallel=1"
	@echo "  make release=1 parallel=1"
	@echo "  make install release=1 parallel=1"

build:
	shards build $(SHARDS_BUILD_FLAGS) $(CRYSTAL_DEFINE_FLAGS)

test: test-unit test-integration

test-unit:
	crystal spec

test-integration:
	bash spec/integration_test.sh

install:
	@test -x "$(BIN_PATH)" || $(MAKE) build release=$(release) parallel=$(parallel)
	mkdir -p "$(INSTALL_DIR)"
	cp "$(BIN_PATH)" "$(INSTALL_DIR)/$(BINARY)"
	chmod +x "$(INSTALL_DIR)/$(BINARY)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(BINARY)"

clean:
	rm -f "$(BIN_PATH)"
