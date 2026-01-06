EXTENSION    = amqp
EXTVERSION   = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")
PG_CONFIG   ?= pg_config
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)

# Detect OS for platform-specific handling
ifeq ($(OS),Windows_NT)
    PLATFORM = windows
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Darwin)
        PLATFORM = darwin
    else
        PLATFORM = linux
    endif
endif

# Test configuration
# Basic tests (no external dependencies)
REGRESS      = 00_extension 01_broker_config 02_functions 03_error_handling 05_ssl 99_cleanup
# Integration tests (require RabbitMQ)
REGRESS_INTEGRATION = 50_integration
# SSL integration tests (require RabbitMQ with SSL on port 5671)
REGRESS_SSL = 51_ssl_integration
REGRESS_OPTS = --inputdir=test --outputdir=test

# librabbitmq version to download
LIBRABBITMQ_VERSION = 0.15.0
LIBRABBITMQ_URL = https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v$(LIBRABBITMQ_VERSION).tar.gz
LIBRABBITMQ_DIR = src/librabbitmq
LIBRABBITMQ_STAMP = $(LIBRABBITMQ_DIR)/.downloaded
LIBRABBITMQ_TARBALL = $(LIBRABBITMQ_DIR)/rabbitmq-c.tar.gz
LIBRABBITMQ_EXTRACTED = $(LIBRABBITMQ_DIR)/rabbitmq-c-$(LIBRABBITMQ_VERSION)

ifeq ($(PG91),yes)
DOCS         = $(wildcard doc/*.*)
MODULE_big   = $(patsubst src/%.c,%,$(wildcard src/*.c))
OBJS         = src/pg_amqp.o \
	$(LIBRABBITMQ_DIR)/amqp_api.o \
	$(LIBRABBITMQ_DIR)/amqp_connection.o \
	$(LIBRABBITMQ_DIR)/amqp_consumer.o \
	$(LIBRABBITMQ_DIR)/amqp_framing.o \
	$(LIBRABBITMQ_DIR)/amqp_mem.o \
	$(LIBRABBITMQ_DIR)/amqp_socket.o \
	$(LIBRABBITMQ_DIR)/amqp_table.o \
	$(LIBRABBITMQ_DIR)/amqp_tcp_socket.o \
	$(LIBRABBITMQ_DIR)/amqp_time.o \
	$(LIBRABBITMQ_DIR)/amqp_url.o \
	$(LIBRABBITMQ_DIR)/amqp_openssl.o \
	$(LIBRABBITMQ_DIR)/amqp_openssl_bio.o

# OpenSSL support for SSL/TLS connections
# Try pkg-config first, fall back to standard flags
OPENSSL_CFLAGS := $(shell pkg-config --cflags-only-I openssl 2>/dev/null)
OPENSSL_LIBS := $(shell pkg-config --libs openssl 2>/dev/null)
ifeq ($(OPENSSL_LIBS),)
    # Fallback for systems without pkg-config (e.g., Windows)
    ifeq ($(PLATFORM),windows)
        OPENSSL_LIBS = -lssl -lcrypto -lws2_32 -lgdi32 -lcrypt32
    else
        OPENSSL_LIBS = -lssl -lcrypto
    endif
endif

override PG_CPPFLAGS += $(OPENSSL_CFLAGS)
override PG_CPPFLAGS += -DHAVE_CONFIG_H=1
SHLIB_LINK += $(OPENSSL_LIBS)

# Windows needs additional libraries
ifeq ($(PLATFORM),windows)
    SHLIB_LINK += -lws2_32
endif

# Check if librabbitmq needs downloading, then recursively call make
all: download-deps

download-deps:
	@if [ ! -f $(LIBRABBITMQ_STAMP) ]; then \
		$(MAKE) $(LIBRABBITMQ_STAMP); \
		$(MAKE) build-extension; \
	else \
		$(MAKE) build-extension; \
	fi

build-extension: sql/$(EXTENSION)--$(EXTVERSION).sql

sql/$(EXTENSION)--$(EXTVERSION).sql: sql/tables/*.sql sql/functions/*.sql
	cat $^ > $@

DATA = $(wildcard updates/*--*.sql) sql/$(EXTENSION)--$(EXTVERSION).sql
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql $(LIBRABBITMQ_DIR)/*.c $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_STAMP) $(LIBRABBITMQ_TARBALL)
else
$(error Minimum version of PostgreSQL required is 9.1.0)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Download and extract librabbitmq source files
# Uses a two-step process (download then extract) for Windows compatibility
$(LIBRABBITMQ_STAMP):
	@echo "Downloading librabbitmq $(LIBRABBITMQ_VERSION)..."
	@mkdir -p $(LIBRABBITMQ_DIR)
	@curl -sL $(LIBRABBITMQ_URL) -o $(LIBRABBITMQ_TARBALL)
	@echo "Extracting librabbitmq..."
	@tar -xzf $(LIBRABBITMQ_TARBALL) -C $(LIBRABBITMQ_DIR)
	@echo "Copying source files..."
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_api.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_connection.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_consumer.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_framing.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_mem.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_socket.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_table.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_tcp_socket.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_time.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_url.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_openssl.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_openssl_bio.c $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_openssl_bio.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_private.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_socket.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_table.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/amqp_time.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/include/rabbitmq-c/amqp.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/include/rabbitmq-c/framing.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/include/rabbitmq-c/tcp_socket.h $(LIBRABBITMQ_DIR)/
	@cp $(LIBRABBITMQ_EXTRACTED)/include/rabbitmq-c/ssl_socket.h $(LIBRABBITMQ_DIR)/
ifeq ($(PLATFORM),windows)
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/win32/threads.h $(LIBRABBITMQ_DIR)/
else
	@cp $(LIBRABBITMQ_EXTRACTED)/librabbitmq/unix/threads.h $(LIBRABBITMQ_DIR)/
endif
	@echo "Fixing includes for flat directory structure..."
	@sed -i.bak 's|#include <rabbitmq-c/\([^>]*\)>|#include "\1"|g' $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_DIR)/*.c
	@sed -i.bak 's|#include "rabbitmq-c/\([^"]*\)"|#include "\1"|g' $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_DIR)/*.c
	@rm -f $(LIBRABBITMQ_DIR)/*.bak
	@echo "Generating config.h..."
ifeq ($(PLATFORM),windows)
	@echo '/* config.h - Generated for pg_amqp (Windows) */' > $(LIBRABBITMQ_DIR)/config.h
	@echo '#ifndef AMQP_CONFIG_H' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_CONFIG_H' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_MAJOR 0' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_MINOR 15' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_PATCH 0' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION "$(LIBRABBITMQ_VERSION)"' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_PLATFORM "pg_amqp-windows"' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_SELECT 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_STDINT_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_INTTYPES_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_WITH_SSL 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_ENABLE_THREAD_SAFETY 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#endif' >> $(LIBRABBITMQ_DIR)/config.h
else
	@echo '/* config.h - Generated for pg_amqp (POSIX) */' > $(LIBRABBITMQ_DIR)/config.h
	@echo '#ifndef AMQP_CONFIG_H' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_CONFIG_H' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_MAJOR 0' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_MINOR 15' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_PATCH 0' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION "$(LIBRABBITMQ_VERSION)"' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_PLATFORM "pg_amqp"' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_PLATFORM_POSIX 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_POLL_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_POLL 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_SELECT 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_STDINT_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_INTTYPES_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_WITH_SSL 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_ENABLE_THREAD_SAFETY 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#endif' >> $(LIBRABBITMQ_DIR)/config.h
endif
	@echo "Generating export.h..."
	@echo '/* export.h - Visibility macros */' > $(LIBRABBITMQ_DIR)/export.h
	@echo '#ifndef RABBITMQ_C_EXPORT_H' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define RABBITMQ_C_EXPORT_H' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_NO_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_DEPRECATED_EXPORT AMQP_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_DEPRECATED_NO_EXPORT AMQP_NO_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#endif' >> $(LIBRABBITMQ_DIR)/export.h
	@rm -rf $(LIBRABBITMQ_EXTRACTED) $(LIBRABBITMQ_TARBALL)
	@touch $@
	@echo "librabbitmq $(LIBRABBITMQ_VERSION) ready."

# Ensure source files exist before compilation
$(OBJS): $(LIBRABBITMQ_STAMP)

# Clean downloaded files
clean: clean-librabbitmq clean-test

clean-librabbitmq:
	rm -f $(LIBRABBITMQ_DIR)/*.c $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_STAMP)
	rm -rf $(LIBRABBITMQ_EXTRACTED) $(LIBRABBITMQ_TARBALL)

clean-test:
	rm -rf test/results test/regression.diffs test/regression.out

# Test targets
# Run basic tests (no external dependencies required)
test: installcheck

# Run integration tests (requires RabbitMQ at localhost:5672)
test-integration:
	$(pg_regress_installcheck) $(REGRESS_OPTS) $(REGRESS_INTEGRATION)

# Run SSL integration tests (requires RabbitMQ with SSL at localhost:5671)
test-ssl:
	$(pg_regress_installcheck) $(REGRESS_OPTS) $(REGRESS_SSL)

# Run all tests including integration tests
test-all:
	$(pg_regress_installcheck) $(REGRESS_OPTS) $(REGRESS) $(REGRESS_INTEGRATION) $(REGRESS_SSL)

# Run full integration tests with message verification (requires RabbitMQ with management plugin)
test-verify:
	@echo "Running integration tests with message verification..."
	./test/integration_test.sh --pg-config $(PG_CONFIG)

.PHONY: clean-librabbitmq clean-test download-deps build-extension test test-integration test-ssl test-all test-verify
