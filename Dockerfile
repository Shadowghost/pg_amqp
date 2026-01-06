# Dockerfile for building pg_amqp extension
#
# Usage:
#   # Build with default PostgreSQL 17
#   docker build -t pg_amqp-builder .
#
#   # Build with specific PostgreSQL version
#   docker build --build-arg PG_VERSION=16 -t pg_amqp-builder:pg16 .
#
#   # Compile the extension
#   docker run --rm -v $(pwd):/build pg_amqp-builder make
#   docker run --rm -v $(pwd):/build pg_amqp-builder make install

ARG PG_VERSION=17
FROM postgres:${PG_VERSION}

ARG PG_VERSION=17

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-${PG_VERSION} \
    libssl-dev \
    pkg-config \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Default command runs make
CMD ["make"]
