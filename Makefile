EXTENSION    = amqp
EXTVERSION   = $(shell grep default_version $(EXTENSION).control | \
               sed -e "s/default_version[[:space:]]*=[[:space:]]*'\([^']*\)'/\1/")
PG_CONFIG   ?= pg_config
PG91         = $(shell $(PG_CONFIG) --version | grep -qE " 8\.| 9\.0" && echo no || echo yes)

# librabbitmq version to download
LIBRABBITMQ_VERSION = 0.15.0
LIBRABBITMQ_URL = https://github.com/alanxz/rabbitmq-c/archive/refs/tags/v$(LIBRABBITMQ_VERSION).tar.gz
LIBRABBITMQ_DIR = src/librabbitmq
LIBRABBITMQ_STAMP = $(LIBRABBITMQ_DIR)/.downloaded

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
override PG_CPPFLAGS += $(shell pkg-config --cflags-only-I openssl 2>/dev/null)
override PG_CPPFLAGS += -DHAVE_CONFIG_H=1
SHLIB_LINK += $(shell pkg-config --libs openssl 2>/dev/null || echo "-lssl -lcrypto")

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
EXTRA_CLEAN = sql/$(EXTENSION)--$(EXTVERSION).sql $(LIBRABBITMQ_DIR)/*.c $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_STAMP)
else
$(error Minimum version of PostgreSQL required is 9.1.0)
endif

PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

# Download and extract librabbitmq source files
$(LIBRABBITMQ_STAMP):
	@echo "Downloading librabbitmq $(LIBRABBITMQ_VERSION)..."
	@mkdir -p $(LIBRABBITMQ_DIR)
	@curl -sL $(LIBRABBITMQ_URL) | tar -xzf - --strip-components=2 -C $(LIBRABBITMQ_DIR) \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_api.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_connection.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_consumer.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_framing.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_mem.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_socket.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_table.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_tcp_socket.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_time.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_url.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_openssl.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_openssl_bio.c \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_openssl_bio.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_private.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_socket.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_table.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/amqp_time.h
	@curl -sL $(LIBRABBITMQ_URL) | tar -xzf - --strip-components=3 -C $(LIBRABBITMQ_DIR) \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/include/rabbitmq-c/amqp.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/include/rabbitmq-c/framing.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/include/rabbitmq-c/tcp_socket.h \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/include/rabbitmq-c/ssl_socket.h
	@curl -sL $(LIBRABBITMQ_URL) | tar -xzf - --strip-components=3 -C $(LIBRABBITMQ_DIR) \
		rabbitmq-c-$(LIBRABBITMQ_VERSION)/librabbitmq/unix/threads.h
	@echo "Fixing includes for flat directory structure..."
	@sed -i 's|#include <rabbitmq-c/\([^>]*\)>|#include "\1"|g' $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_DIR)/*.c
	@sed -i 's|#include "rabbitmq-c/\([^"]*\)"|#include "\1"|g' $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_DIR)/*.c
	@echo "Generating config.h and export.h..."
	@echo '/* config.h - Generated for pg_amqp with librabbitmq $(LIBRABBITMQ_VERSION) */' > $(LIBRABBITMQ_DIR)/config.h
	@echo '#ifndef AMQP_CONFIG_H' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_CONFIG_H' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '/* Version info */' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_MAJOR 0' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_MINOR 15' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION_PATCH 0' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_VERSION "$(LIBRABBITMQ_VERSION)"' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_PLATFORM "pg_amqp"' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '/* Platform features - always enabled for POSIX systems */' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQ_PLATFORM_POSIX 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_POLL_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_POLL 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_SELECT 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_STDINT_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define HAVE_INTTYPES_H 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '/* SSL and thread safety - always enabled */' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_WITH_SSL 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#define AMQP_ENABLE_THREAD_SAFETY 1' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '#endif /* AMQP_CONFIG_H */' >> $(LIBRABBITMQ_DIR)/config.h
	@echo '/* export.h - Visibility macros for bundled library */' > $(LIBRABBITMQ_DIR)/export.h
	@echo '#ifndef RABBITMQ_C_EXPORT_H' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define RABBITMQ_C_EXPORT_H' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_NO_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_DEPRECATED_EXPORT AMQP_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#define AMQP_DEPRECATED_NO_EXPORT AMQP_NO_EXPORT' >> $(LIBRABBITMQ_DIR)/export.h
	@echo '#endif' >> $(LIBRABBITMQ_DIR)/export.h
	@touch $@
	@echo "librabbitmq $(LIBRABBITMQ_VERSION) ready."

# Ensure source files exist before compilation
$(OBJS): $(LIBRABBITMQ_STAMP)

# Clean downloaded files
clean: clean-librabbitmq

clean-librabbitmq:
	rm -f $(LIBRABBITMQ_DIR)/*.c $(LIBRABBITMQ_DIR)/*.h $(LIBRABBITMQ_STAMP)

.PHONY: clean-librabbitmq download-deps build-extension
