#!/bin/bash
# Local test runner for pg_amqp
# Usage: ./test/run_tests.sh [options]
#
# Options:
#   --basic           Run only basic tests (no RabbitMQ required)
#   --integration     Run only integration tests (requires RabbitMQ)
#   --verify          Run message verification tests (requires RabbitMQ management)
#   --all             Run all tests including verification (default)
#   --pg-config PATH  Path to pg_config (default: auto-detect, prefers PostgreSQL 17)
#   --start-rabbitmq  Start RabbitMQ container before tests
#   --stop-rabbitmq   Stop RabbitMQ container after tests
#   --help            Show this help message
#
# Examples:
#   ./test/run_tests.sh --basic
#   ./test/run_tests.sh --start-rabbitmq --all
#   ./test/run_tests.sh --pg-config /usr/lib/postgresql/17/bin/pg_config --all

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Default settings
RUN_BASIC=true
RUN_INTEGRATION=true
RUN_SSL_INTEGRATION=true
RUN_VERIFY=true
START_RABBITMQ=false
STOP_RABBITMQ=false
RABBITMQ_CONTAINER_NAME="pg_amqp_test_rabbitmq"
PG_CONFIG=""
USE_DOCKER_COMPOSE=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << 'EOF'
pg_amqp Test Runner

Usage: ./test/run_tests.sh [options]

Options:
  --basic           Run only basic tests (no RabbitMQ required)
  --integration     Run only integration tests (requires RabbitMQ)
  --ssl             Run only SSL integration tests (requires RabbitMQ with SSL)
  --verify          Run only message verification tests (requires RabbitMQ management)
  --all             Run all tests including SSL and verification (default)
  --pg-config PATH  Path to pg_config (default: auto-detect, prefers PostgreSQL 17)
  --start-rabbitmq  Start RabbitMQ container before tests (with SSL support)
  --stop-rabbitmq   Stop RabbitMQ container after tests
  --help            Show this help message

Examples:
  # Run basic tests only
  ./test/run_tests.sh --basic

  # Run all tests with automatic RabbitMQ management
  ./test/run_tests.sh --start-rabbitmq --stop-rabbitmq --all

  # Use specific PostgreSQL version
  ./test/run_tests.sh --pg-config /usr/lib/postgresql/17/bin/pg_config --all

  # Run SSL integration tests only
  ./test/run_tests.sh --start-rabbitmq --ssl

  # Run message verification tests only
  ./test/run_tests.sh --start-rabbitmq --verify
EOF
    exit 0
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --basic)
            RUN_BASIC=true
            RUN_INTEGRATION=false
            RUN_SSL_INTEGRATION=false
            RUN_VERIFY=false
            shift
            ;;
        --integration)
            RUN_BASIC=false
            RUN_INTEGRATION=true
            RUN_SSL_INTEGRATION=false
            RUN_VERIFY=false
            shift
            ;;
        --ssl)
            RUN_BASIC=false
            RUN_INTEGRATION=false
            RUN_SSL_INTEGRATION=true
            RUN_VERIFY=false
            shift
            ;;
        --verify)
            RUN_BASIC=false
            RUN_INTEGRATION=false
            RUN_SSL_INTEGRATION=false
            RUN_VERIFY=true
            shift
            ;;
        --all)
            RUN_BASIC=true
            RUN_INTEGRATION=true
            RUN_SSL_INTEGRATION=true
            RUN_VERIFY=true
            shift
            ;;
        --pg-config)
            PG_CONFIG="$2"
            shift 2
            ;;
        --start-rabbitmq)
            START_RABBITMQ=true
            shift
            ;;
        --stop-rabbitmq)
            STOP_RABBITMQ=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Find pg_config, preferring PostgreSQL 17
find_pg_config() {
    if [ -n "$PG_CONFIG" ]; then
        if [ -x "$PG_CONFIG" ]; then
            echo "$PG_CONFIG"
            return 0
        else
            log_error "Specified pg_config not found or not executable: $PG_CONFIG"
            exit 1
        fi
    fi

    # Try PostgreSQL 17 first, then fall back to other versions
    local pg_paths=(
        "/usr/lib/postgresql/17/bin/pg_config"
        "/usr/lib/postgresql/16/bin/pg_config"
        "/usr/lib/postgresql/15/bin/pg_config"
        "/usr/lib/postgresql/14/bin/pg_config"
        "/usr/pgsql-17/bin/pg_config"
        "/usr/pgsql-16/bin/pg_config"
        "/opt/homebrew/opt/postgresql@17/bin/pg_config"
        "/opt/homebrew/opt/postgresql@16/bin/pg_config"
        "/usr/local/opt/postgresql@17/bin/pg_config"
        "/usr/local/opt/postgresql@16/bin/pg_config"
    )

    for pg_path in "${pg_paths[@]}"; do
        if [ -x "$pg_path" ]; then
            echo "$pg_path"
            return 0
        fi
    done

    # Fall back to PATH
    if command -v pg_config &> /dev/null; then
        command -v pg_config
        return 0
    fi

    return 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Find pg_config
    PG_CONFIG=$(find_pg_config) || {
        log_error "pg_config not found. Please install PostgreSQL 17 development packages."
        log_error "Or specify path with --pg-config /path/to/pg_config"
        exit 1
    }

    local pg_version=$("$PG_CONFIG" --version)
    log_info "Using PostgreSQL: $pg_version"
    log_info "pg_config: $PG_CONFIG"

    # Check if extension is built
    if [ ! -f "pg_amqp.so" ]; then
        log_warn "Extension not built. Running 'make' first..."
        make PG_CONFIG="$PG_CONFIG"
    fi

    # Check if extension is installed
    local pg_lib_dir=$("$PG_CONFIG" --pkglibdir)
    if [ ! -f "$pg_lib_dir/pg_amqp.so" ]; then
        log_warn "Extension not installed. Running 'make install' (may require sudo)..."
        sudo make install PG_CONFIG="$PG_CONFIG" || make install PG_CONFIG="$PG_CONFIG"
    fi

    log_info "Prerequisites satisfied."
}

# Generate SSL certificates if needed
generate_ssl_certs() {
    local certs_dir="$SCRIPT_DIR/ssl/certs"
    if [ ! -f "$certs_dir/server.crt" ]; then
        log_info "Generating SSL certificates..."
        chmod +x "$SCRIPT_DIR/ssl/generate_certs.sh"
        "$SCRIPT_DIR/ssl/generate_certs.sh"
    else
        log_info "SSL certificates already exist."
    fi
}

# Start RabbitMQ container
start_rabbitmq() {
    if [ "$START_RABBITMQ" = true ]; then
        log_info "Starting RabbitMQ container with SSL support..."

        # Check if Docker is available
        if ! command -v docker &> /dev/null; then
            log_error "Docker not found. Please install Docker or start RabbitMQ manually."
            exit 1
        fi

        # Generate SSL certificates if needed
        generate_ssl_certs

        # Check if docker-compose or docker compose is available
        local compose_cmd=""
        if command -v docker-compose &> /dev/null; then
            compose_cmd="docker-compose"
        elif docker compose version &> /dev/null; then
            compose_cmd="docker compose"
        fi

        if [ -n "$compose_cmd" ] && [ "$USE_DOCKER_COMPOSE" = true ]; then
            # Use docker-compose for SSL-enabled RabbitMQ
            log_info "Using docker-compose for RabbitMQ with SSL..."
            $compose_cmd -f docker-compose.yml up -d rabbitmq
        else
            # Fall back to direct docker run (without SSL)
            log_warn "docker-compose not found, starting RabbitMQ without SSL support..."

            # Check if container already exists
            if docker ps -a --format '{{.Names}}' | grep -q "^${RABBITMQ_CONTAINER_NAME}$"; then
                if docker ps --format '{{.Names}}' | grep -q "^${RABBITMQ_CONTAINER_NAME}$"; then
                    log_info "RabbitMQ container already running."
                else
                    log_info "Starting existing RabbitMQ container..."
                    docker start "$RABBITMQ_CONTAINER_NAME"
                fi
            else
                log_info "Creating new RabbitMQ container..."
                docker run -d \
                    --name "$RABBITMQ_CONTAINER_NAME" \
                    -p 5672:5672 \
                    -p 15672:15672 \
                    rabbitmq:3-management
            fi
        fi

        # Wait for RabbitMQ to be ready (standard port)
        log_info "Waiting for RabbitMQ to be ready..."
        for i in {1..30}; do
            if nc -z localhost 5672 2>/dev/null; then
                log_info "RabbitMQ AMQP port (5672) is ready!"
                break
            fi
            if [ $i -eq 30 ]; then
                log_error "Timeout waiting for RabbitMQ"
                exit 1
            fi
            echo -n "."
            sleep 1
        done

        # Wait for SSL port if using docker-compose
        if [ -n "$compose_cmd" ] && [ "$USE_DOCKER_COMPOSE" = true ]; then
            log_info "Waiting for RabbitMQ SSL port..."
            for i in {1..30}; do
                if nc -z localhost 5671 2>/dev/null; then
                    log_info "RabbitMQ SSL port (5671) is ready!"
                    return 0
                fi
                if [ $i -eq 30 ]; then
                    log_warn "RabbitMQ SSL port not available, SSL tests may fail"
                    return 0
                fi
                echo -n "."
                sleep 1
            done
        fi
    fi
}

# Stop RabbitMQ container
stop_rabbitmq() {
    if [ "$STOP_RABBITMQ" = true ]; then
        log_info "Stopping RabbitMQ container..."

        # Check if docker-compose or docker compose is available
        local compose_cmd=""
        if command -v docker-compose &> /dev/null; then
            compose_cmd="docker-compose"
        elif docker compose version &> /dev/null; then
            compose_cmd="docker compose"
        fi

        if [ -n "$compose_cmd" ] && [ "$USE_DOCKER_COMPOSE" = true ]; then
            $compose_cmd -f docker-compose.yml down
        else
            docker stop "$RABBITMQ_CONTAINER_NAME" 2>/dev/null || true
            docker rm "$RABBITMQ_CONTAINER_NAME" 2>/dev/null || true
        fi
        log_info "RabbitMQ container stopped and removed."
    fi
}

# Check if RabbitMQ SSL port is available
check_rabbitmq_ssl() {
    if nc -z localhost 5671 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Check if RabbitMQ is available
check_rabbitmq() {
    if nc -z localhost 5672 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Run basic tests
run_basic_tests() {
    if [ "$RUN_BASIC" = true ]; then
        log_info "Running basic tests..."
        if make test PG_CONFIG="$PG_CONFIG"; then
            log_info "Basic tests passed!"
            return 0
        else
            log_error "Basic tests failed!"
            if [ -f test/regression.diffs ]; then
                log_error "Test differences:"
                cat test/regression.diffs
            fi
            return 1
        fi
    fi
    return 0
}

# Run integration tests
run_integration_tests() {
    if [ "$RUN_INTEGRATION" = true ]; then
        log_info "Running integration tests..."

        if ! check_rabbitmq; then
            if [ "$START_RABBITMQ" = false ]; then
                log_warn "RabbitMQ not available at localhost:5672"
                log_warn "Skipping integration tests. Use --start-rabbitmq to start RabbitMQ automatically."
                return 0
            fi
        fi

        if make test-integration PG_CONFIG="$PG_CONFIG"; then
            log_info "Integration tests passed!"
            return 0
        else
            log_error "Integration tests failed!"
            if [ -f test/regression.diffs ]; then
                log_error "Test differences:"
                cat test/regression.diffs
            fi
            return 1
        fi
    fi
    return 0
}

# Run SSL integration tests
run_ssl_integration_tests() {
    if [ "$RUN_SSL_INTEGRATION" = true ]; then
        log_info "Running SSL integration tests..."

        if ! check_rabbitmq_ssl; then
            if [ "$START_RABBITMQ" = false ]; then
                log_warn "RabbitMQ SSL not available at localhost:5671"
                log_warn "Skipping SSL integration tests. Use --start-rabbitmq to start RabbitMQ with SSL."
                return 0
            else
                log_warn "RabbitMQ SSL port (5671) not available"
                log_warn "Skipping SSL integration tests."
                return 0
            fi
        fi

        if make test-ssl PG_CONFIG="$PG_CONFIG"; then
            log_info "SSL integration tests passed!"
            return 0
        else
            log_error "SSL integration tests failed!"
            if [ -f test/regression.diffs ]; then
                log_error "Test differences:"
                cat test/regression.diffs
            fi
            return 1
        fi
    fi
    return 0
}

# Run message verification tests
run_verify_tests() {
    if [ "$RUN_VERIFY" = true ]; then
        log_info "Running message verification tests..."

        if ! check_rabbitmq; then
            if [ "$START_RABBITMQ" = false ]; then
                log_warn "RabbitMQ not available at localhost:5672"
                log_warn "Skipping verification tests. Use --start-rabbitmq to start RabbitMQ automatically."
                return 0
            fi
        fi

        # Check if Python 3 is available
        if ! command -v python3 &> /dev/null; then
            log_warn "Python 3 not found. Skipping message verification tests."
            return 0
        fi

        if make test-verify PG_CONFIG="$PG_CONFIG"; then
            log_info "Message verification tests passed!"
            return 0
        else
            log_error "Message verification tests failed!"
            return 1
        fi
    fi
    return 0
}

# Main execution
main() {
    echo ""
    log_info "========================================="
    log_info "       pg_amqp Test Runner"
    log_info "========================================="
    echo ""

    check_prerequisites
    start_rabbitmq

    local exit_code=0

    echo ""
    if ! run_basic_tests; then
        exit_code=1
    fi

    echo ""
    if ! run_integration_tests; then
        exit_code=1
    fi

    echo ""
    if ! run_ssl_integration_tests; then
        exit_code=1
    fi

    echo ""
    if ! run_verify_tests; then
        exit_code=1
    fi

    echo ""
    stop_rabbitmq

    echo ""
    log_info "========================================="
    if [ $exit_code -eq 0 ]; then
        log_info "       All tests passed!"
    else
        log_error "       Some tests failed!"
    fi
    log_info "========================================="
    echo ""

    exit $exit_code
}

main
