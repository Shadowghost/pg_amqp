# Dockerfile for building pg_amqp extension
# Usage:
#   docker build -t pg_amqp-builder .
#   docker run --rm -v $(pwd):/build pg_amqp-builder make
#   docker run --rm -v $(pwd):/build pg_amqp-builder make install

FROM postgres:16

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-16 \
    libssl-dev \
    pkg-config \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Default command runs make
CMD ["make"]
