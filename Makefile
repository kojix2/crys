SHELL := /bin/sh

BINARY := crys
BIN_DIR := bin
BIN_PATH := $(BIN_DIR)/$(BINARY)
PREFIX ?= $(HOME)/.local
INSTALL_DIR ?= $(PREFIX)/bin

release ?= 0
parallel ?= 0

CRYSTAL_FLAGS :=

ifeq ($(release),1)
CRYSTAL_FLAGS += --release
endif

ifeq ($(parallel),1)
CRYSTAL_FLAGS += -Dpreview_mt -Dexecution_context
endif

.PHONY: help build test test-unit test-integration install uninstall clean

help:
	@echo "Available targets:"
	@echo "  build            Build $(BIN_PATH) (release=1 parallel=1 supported)"
	@echo "  test             Run unit + integration tests"
	@echo "  test-unit        Run unit tests"
	@echo "  test-integration Run integration tests"
	@echo "  install          Install $(BINARY) to $(INSTALL_DIR)"
	@echo "  uninstall        Remove installed binary"
	@echo "  clean            Remove built binary"
	@echo ""
	@echo "Examples:"
	@echo "  make build release=1"
	@echo "  make build parallel=1"
	@echo "  make build release=1 parallel=1"

build:
	shards build $(if $(CRYSTAL_FLAGS),-- $(CRYSTAL_FLAGS),)

test: test-unit test-integration

test-unit:
	crystal spec

test-integration:
	bash spec/integration_test.sh

install: build
	mkdir -p "$(INSTALL_DIR)"
	cp "$(BIN_PATH)" "$(INSTALL_DIR)/$(BINARY)"
	chmod +x "$(INSTALL_DIR)/$(BINARY)"

uninstall:
	rm -f "$(INSTALL_DIR)/$(BINARY)"

clean:
	rm -f "$(BIN_PATH)"
