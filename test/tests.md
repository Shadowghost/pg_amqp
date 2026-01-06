# pg_amqp Test Suite

This directory contains the test suite for pg_amqp using PostgreSQL's `pg_regress` framework and message verification scripts.

## Prerequisites

- PostgreSQL 17 (or 14+) with development headers installed
- pg_amqp extension built and installed (`make && sudo make install`)
- For integration tests: RabbitMQ running at `localhost:5672` with default `guest/guest` credentials
- For message verification tests: RabbitMQ management plugin enabled (port 15672) and Python 3

## Test Files

### SQL Regression Tests

**Basic Tests** (no external dependencies):

| Test | File | Description |
|------|------|-------------|
| Extension | `00_extension.sql` | Extension creation, schema validation, table structure |
| Broker Config | `01_broker_config.sql` | Broker table CRUD operations, SSL configuration |
| Functions | `02_functions.sql` | Function signatures, argument types, metadata |
| Error Handling | `03_error_handling.sql` | Graceful error handling without broker connection |
| SSL Config | `05_ssl.sql` | SSL configuration options and validation |
| Cleanup | `99_cleanup.sql` | Extension drop/recreate verification |

**Integration Tests** (require RabbitMQ):

| Test | File | Description |
|------|------|-------------|
| Integration | `50_integration.sql` | Full integration tests with message publishing (port 5672) |
| SSL Integration | `51_ssl_integration.sql` | SSL/TLS integration with secure broker (port 5671) |

### Message Verification Tests

| File | Description |
|------|-------------|
| `integration_test.sh` | End-to-end tests that verify messages arrive at the broker |
| `verify_messages.py` | Python script to interact with RabbitMQ Management API |

The message verification tests check:
- Autonomous publish delivers messages immediately
- Transactional publish delivers on COMMIT
- Transactional publish does NOT deliver on ROLLBACK
- Multiple messages in a single transaction
- Message properties (delivery_mode, content_type, etc.)
- Reconnect after disconnect
- Large messages (10KB)
- Special characters and Unicode

## Running Tests

### Using Make (Recommended)

```bash
# Run basic tests (no RabbitMQ required)
make test
# or
make installcheck

# Run integration tests (requires RabbitMQ at localhost:5672)
make test-integration

# Run SSL integration tests (requires RabbitMQ with SSL at localhost:5671)
make test-ssl

# Run all SQL tests
make test-all

# Run message verification tests (requires RabbitMQ with management plugin)
make test-verify
```

### Using the Test Runner Script

The `run_tests.sh` script provides a convenient way to run tests locally:

```bash
# Show help
./test/run_tests.sh --help

# Run basic tests only (no external dependencies)
./test/run_tests.sh --basic

# Run integration tests only (RabbitMQ must be running)
./test/run_tests.sh --integration

# Run SSL integration tests only (RabbitMQ with SSL must be running)
./test/run_tests.sh --ssl

# Run message verification tests only
./test/run_tests.sh --verify

# Run all tests (basic + integration + ssl + verification)
./test/run_tests.sh --all

# Start RabbitMQ container automatically before tests
./test/run_tests.sh --start-rabbitmq --all

# Stop RabbitMQ container after tests complete
./test/run_tests.sh --start-rabbitmq --stop-rabbitmq --all
```

### Using Docker Compose

Start test dependencies with Docker Compose:

```bash
# Start RabbitMQ (and optionally PostgreSQL)
docker-compose -f docker-compose.test.yml up -d

# Run tests
make test-all

# Stop services when done
docker-compose -f docker-compose.test.yml down
```

## Quick Start

Run all tests with automatic RabbitMQ management:

```bash
# Build and install the extension
make
sudo make install

# Run all tests (starts RabbitMQ automatically)
./test/run_tests.sh --start-rabbitmq --stop-rabbitmq --all
```

## Test Output

Test results are written to the `test/` directory:

| File | Description |
|------|-------------|
| `results/*.out` | Actual output from each test |
| `regression.diffs` | Differences between expected and actual output (only on failure) |
| `regression.out` | Summary of test execution |

## Viewing Test Failures

If tests fail, check the differences:

```bash
cat test/regression.diffs
```

Compare expected vs actual output:

```bash
diff test/expected/00_extension.out test/results/00_extension.out
```

## Writing New Tests

1. Create a new SQL file in `test/sql/` (e.g., `06_new_test.sql`)
2. Create the expected output in `test/expected/` (e.g., `06_new_test.out`)
3. Add the test name to `REGRESS` or `REGRESS_INTEGRATION` in `Makefile`

To generate expected output, run the test manually and capture output:

```bash
psql -f test/sql/06_new_test.sql > test/expected/06_new_test.out 2>&1
```

Then review and adjust the output file as needed.

## CI Integration

Tests run automatically in GitHub Actions on push/PR to `master` or `main` branches:

- **test-linux**: Runs all tests (basic, integration, SSL) on PostgreSQL 14, 15, 16, 17 with RabbitMQ
- **build-windows**: Verifies Windows build with MSYS2/MinGW on PostgreSQL 16, 17
- **build-docker**: Verifies the Dockerfile builds correctly

## Troubleshooting

### PostgreSQL not found

Ensure `pg_config` is in your PATH:

```bash
export PATH="/usr/lib/postgresql/17/bin:$PATH"
```

Or specify it explicitly:

```bash
make test PG_CONFIG=/usr/lib/postgresql/17/bin/pg_config
```

### Extension not installed

Install the extension before running tests:

```bash
sudo make install
```

### RabbitMQ connection refused

Start RabbitMQ or use the test script:

```bash
# Using Docker
docker run -d --name rabbitmq -p 5672:5672 rabbitmq:3-management

# Or use the test script
./test/run_tests.sh --start-rabbitmq --integration
```

### Permission denied

Run installation with sudo:

```bash
sudo make install
```

### Tests pass locally but fail in CI

Check for environment differences:
- PostgreSQL version
- Extension version in `amqp.control`
- RabbitMQ availability and credentials
