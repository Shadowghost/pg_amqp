#!/bin/bash
# Integration test for pg_amqp with message verification
#
# Prerequisites:
#   - PostgreSQL running with pg_amqp extension installed
#   - RabbitMQ running at localhost:5672 with management plugin (port 15672)
#   - Python 3 available
#
# Usage:
#   ./test/integration_test.sh [--pg-config PATH]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
PG_CONFIG="${PG_CONFIG:-pg_config}"
PSQL="psql"
VERIFY_SCRIPT="$SCRIPT_DIR/verify_messages.py"
TEST_DB="${TEST_DB:-postgres}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --pg-config)
            PG_CONFIG="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_test() { echo -e "${GREEN}[TEST]${NC} $1"; }

# Track test results
TESTS_PASSED=0
TESTS_FAILED=0

run_test() {
    local name="$1"
    local test_func="$2"
    local output
    local result

    output=$($test_func 2>&1) && result=0 || result=$?

    if [ "$result" -eq 0 ]; then
        log_test "PASS: $name"
        ((TESTS_PASSED++)) || true
    else
        log_test "FAIL: $name"
        echo "$output" | sed 's/^/       /'
        ((TESTS_FAILED++)) || true
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found"
        exit 1
    fi

    if ! command -v "$PSQL" &> /dev/null; then
        log_error "psql not found"
        exit 1
    fi

    local rabbitmq_host="${RABBITMQ_HOST:-localhost}"
    log_info "Checking RabbitMQ Management API at $rabbitmq_host:15672..."
    if ! python3 "$VERIFY_SCRIPT" check; then
        log_error "Cannot connect to RabbitMQ Management API"
        exit 1
    fi

    log_info "Prerequisites OK"
}

setup() {
    log_info "Setting up test environment..."

    python3 "$VERIFY_SCRIPT" setup

    # Use AMQP_BROKER_HOST env var if set, otherwise localhost
    local broker_host="${AMQP_BROKER_HOST:-localhost}"

    $PSQL -d "$TEST_DB" -q << EOF
DROP EXTENSION IF EXISTS amqp CASCADE;
CREATE EXTENSION amqp;
INSERT INTO amqp.broker (host, port, vhost, username, password)
VALUES ('$broker_host', 5672, '/', 'guest', 'guest');
EOF

    log_info "Setup complete"
}

cleanup() {
    log_info "Cleaning up..."
    python3 "$VERIFY_SCRIPT" cleanup 2>/dev/null || true
    $PSQL -d "$TEST_DB" -q -c "DROP EXTENSION IF EXISTS amqp CASCADE;" 2>/dev/null || true
    log_info "Cleanup complete"
}

# Test: Basic autonomous publish
test_autonomous_publish() {
    log_info "Testing autonomous publish..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q -c \
        "SELECT amqp.autonomous_publish(1, 'pg_amqp_verify_exchange', 'test.basic', 'Hello from autonomous publish!');"

    python3 "$VERIFY_SCRIPT" verify-message "Hello from autonomous publish!"
}

# Test: Transactional publish with commit
test_transactional_publish_commit() {
    log_info "Testing transactional publish with COMMIT..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q << 'EOF'
BEGIN;
SELECT amqp.publish(1, 'pg_amqp_verify_exchange', 'test.txn', 'Transactional message - should arrive');
COMMIT;
EOF

    python3 "$VERIFY_SCRIPT" verify-message "Transactional message - should arrive"
}

# Test: Transactional publish with rollback (message should NOT arrive)
test_transactional_publish_rollback() {
    log_info "Testing transactional publish with ROLLBACK..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q << 'EOF'
BEGIN;
SELECT amqp.publish(1, 'pg_amqp_verify_exchange', 'test.rollback', 'This message should NOT arrive');
ROLLBACK;
EOF

    python3 "$VERIFY_SCRIPT" verify-empty
}

# Test: Multiple transactional messages
# Uses transactional publish to verify multiple messages arrive reliably.
# autonomous_publish is fire-and-forget and doesn't guarantee delivery.
test_multiple_messages() {
    log_info "Testing multiple transactional messages..."
    python3 "$VERIFY_SCRIPT" purge

    # Note: pg_sleep after COMMIT ensures the PostgreSQL backend stays alive
    # long enough for the AMQP connection to transmit messages before exit.
    $PSQL -d "$TEST_DB" -q << 'EOF'
BEGIN;
SELECT amqp.publish(1, 'pg_amqp_verify_exchange', 'batch.1', 'Batch message 1');
SELECT amqp.publish(1, 'pg_amqp_verify_exchange', 'batch.2', 'Batch message 2');
SELECT amqp.publish(1, 'pg_amqp_verify_exchange', 'batch.3', 'Batch message 3');
COMMIT;
SELECT pg_sleep(0.1);
EOF

    python3 "$VERIFY_SCRIPT" verify 3
}

# Test: Message with properties
test_message_properties() {
    log_info "Testing message with properties..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q << 'EOF'
SELECT amqp.autonomous_publish(
    1,
    'pg_amqp_verify_exchange',
    'test.props',
    '{"data": "test"}',
    2,                    -- delivery_mode (persistent)
    'application/json',   -- content_type
    'reply.queue',        -- reply_to
    'correlation-123'     -- correlation_id
);
EOF

    python3 "$VERIFY_SCRIPT" verify-message '{"data": "test"}'
}

# Test: Reconnect after disconnect
test_reconnect() {
    log_info "Testing reconnect after disconnect..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q << 'EOF'
SELECT amqp.autonomous_publish(1, 'pg_amqp_verify_exchange', 'test.before', 'Before disconnect');
SELECT amqp.disconnect(1);
SELECT amqp.autonomous_publish(1, 'pg_amqp_verify_exchange', 'test.after', 'After reconnect');
EOF

    python3 "$VERIFY_SCRIPT" verify 2
}

# Test: Large message (10KB)
test_large_message() {
    log_info "Testing large message..."
    python3 "$VERIFY_SCRIPT" purge

    local large_msg=$(python3 -c "print('X' * 10000)")

    $PSQL -d "$TEST_DB" -q -c \
        "SELECT amqp.autonomous_publish(1, 'pg_amqp_verify_exchange', 'test.large', '$large_msg');"

    python3 "$VERIFY_SCRIPT" verify 1
}

# Test: Special characters in message
test_special_characters() {
    log_info "Testing special characters in message..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q -c \
        "SELECT amqp.autonomous_publish(1, 'pg_amqp_verify_exchange', 'test.special', E'Special chars: \\n\\t\"quotes\" <xml> & ampersand');"

    python3 "$VERIFY_SCRIPT" verify 1
}

# Test: Unicode message
test_unicode_message() {
    log_info "Testing unicode message..."
    python3 "$VERIFY_SCRIPT" purge

    $PSQL -d "$TEST_DB" -q -c \
        "SELECT amqp.autonomous_publish(1, 'pg_amqp_verify_exchange', 'test.unicode', 'Unicode: 你好世界 🎉 émojis');"

    python3 "$VERIFY_SCRIPT" verify-message 'Unicode: 你好世界 🎉 émojis'
}

main() {
    echo ""
    log_info "========================================="
    log_info "  pg_amqp Integration Tests"
    log_info "========================================="
    echo ""

    check_prerequisites

    trap cleanup EXIT

    setup
    echo ""

    run_test "Autonomous publish" test_autonomous_publish
    run_test "Transactional publish (commit)" test_transactional_publish_commit
    run_test "Transactional publish (rollback)" test_transactional_publish_rollback
    run_test "Multiple transactional messages" test_multiple_messages
    run_test "Message with properties" test_message_properties
    run_test "Reconnect after disconnect" test_reconnect
    run_test "Large message (10KB)" test_large_message
    run_test "Special characters" test_special_characters
    run_test "Unicode message" test_unicode_message

    echo ""
    log_info "========================================="
    log_info "  Results: $TESTS_PASSED passed, $TESTS_FAILED failed"
    log_info "========================================="
    echo ""

    [ "$TESTS_FAILED" -eq 0 ]
}

main "$@"
