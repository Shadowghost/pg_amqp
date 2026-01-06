#!/bin/bash
# Integration test runner for Docker environment
set -e

BROKER_HOST="${RABBITMQ_HOST:-localhost}"
echo "Using RabbitMQ host: $BROKER_HOST"

echo "Waiting for RabbitMQ at $BROKER_HOST:5672..."
for i in $(seq 1 30); do
    if nc -z "$BROKER_HOST" 5672 2>/dev/null; then
        echo "RabbitMQ is ready"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "Timeout waiting for RabbitMQ"
        exit 1
    fi
    sleep 1
done

echo "Starting PostgreSQL..."
su postgres -c "pg_ctl start -D /var/lib/postgresql/data -l /var/log/postgresql.log -o '-c listen_addresses=localhost'"
sleep 2

echo "Running integration tests..."
export PGHOST=localhost
export PGUSER=postgres
export TEST_DB=postgres
export RABBITMQ_HOST="$BROKER_HOST"
export AMQP_BROKER_HOST="$BROKER_HOST"

/pg_amqp/test/integration_test.sh
