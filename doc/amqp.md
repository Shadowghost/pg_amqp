pg_amqp
==========

A PostgreSQL extension for publishing messages to AMQP brokers (such as RabbitMQ).

Installation
------------

### Prerequisites

- PostgreSQL 9.1 or later (development headers required)
- OpenSSL development libraries
- curl (for downloading librabbitmq during build)
- pkg-config

### Building

```bash
make
sudo make install
```

### Loading the Extension

```sql
CREATE EXTENSION amqp;
```

Usage
-----

### Broker Configuration

Insert AMQP broker information (host/port/user/pass) into the
`amqp.broker` table.

```sql
INSERT INTO amqp.broker (host, port, vhost, username, password)
VALUES ('localhost', 5672, '/', 'guest', 'guest');
```

### Publishing Messages

A process starts and connects to PostgreSQL and runs:

```sql
SELECT amqp.publish(broker_id, 'amqp.direct', 'foo', 'message', 1,
        'application/json', 'some_reply_to', 'correlation_id');
```

The last four parameters are optional and define the message properties. The parameters
are: delivery_mode (either 1 or 2, non-persistent, persistent respectively), content_type,
reply_to and correlation_id.

Given that message parameters are optional, the function can be called without any of those in
which case no message properties are sent, as in:

```sql
SELECT amqp.publish(broker_id, 'amqp.direct', 'foo', 'message');
```

### Autonomous Publishing

For messages that should be sent immediately regardless of transaction state:

```sql
SELECT amqp.autonomous_publish(broker_id, 'exchange', 'routing_key', 'message');
```

### Exchange Declaration

```sql
SELECT amqp.exchange_declare(broker_id, 'exchange_name', 'direct', false, true, false);
```

Parameters: broker_id, exchange_name, exchange_type, passive, durable, auto_delete

### Disconnecting

Upon process termination, all broker connections will be torn down.
If there is a need to disconnect from a specific broker, one can call:

```sql
SELECT amqp.disconnect(broker_id);
```

which will disconnect from the broker if it is connected and do nothing
if it is already disconnected.

SSL/TLS Support
---------------

pg_amqp supports SSL/TLS connections to AMQP brokers. Configure SSL in the broker table:

```sql
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_cacert, ssl_verify_peer, ssl_verify_hostname)
VALUES ('secure.rabbitmq.example.com', 5671, '/', 'user', 'pass', true, '/etc/ssl/certs/ca-certificates.crt', true, true);
```

SSL columns:
- `ssl` (boolean): Enable SSL/TLS connection
- `ssl_cacert` (text): Path to CA certificate file
- `ssl_verify_peer` (boolean): Verify server certificate (default: true)
- `ssl_verify_hostname` (boolean): Verify hostname matches certificate (default: true)

Testing
-------

pg_amqp includes a comprehensive test suite using PostgreSQL's pg_regress framework.

### Running Basic Tests

Basic tests verify extension functionality without requiring an AMQP broker:

```bash
make test
# or
make installcheck
```

### Running Integration Tests

Integration tests require a RabbitMQ broker running at localhost:5672 with default guest/guest credentials:

```bash
# Start RabbitMQ (using Docker)
docker run -d --name rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management

# Run integration tests
make test-integration
```

### Running All Tests

```bash
make test-all
```

### Using the Test Helper Script

A helper script is provided for easier local testing:

```bash
# Run all tests with automatic RabbitMQ container management
./test/run_tests.sh --start-rabbitmq --all

# Run only basic tests
./test/run_tests.sh --basic

# Run only integration tests (RabbitMQ must be running)
./test/run_tests.sh --integration
```

### Using Docker Compose

A docker-compose file is provided for test dependencies:

```bash
# Start RabbitMQ
docker-compose -f docker-compose.test.yml up -d

# Run tests
make test-all

# Stop services
docker-compose -f docker-compose.test.yml down
```

### Test Structure

**Basic Tests** (no external dependencies):

| Test File | Description |
|-----------|-------------|
| 00_extension | Extension creation and schema validation |
| 01_broker_config | Broker table CRUD operations |
| 02_functions | Function signatures and metadata |
| 03_error_handling | Graceful error handling without broker |
| 05_ssl | SSL configuration options |
| 99_cleanup | Extension drop/recreate verification |

**Integration Tests** (require RabbitMQ):

| Test File | Description |
|-----------|-------------|
| 50_integration | Full integration tests with RabbitMQ (port 5672) |
| 51_ssl_integration | SSL/TLS integration tests (port 5671) |

Support
-------

This library is stored in an open [GitHub
repository](http://github.com/omniti-labs/pg_amqp). Feel free to fork and
contribute! Please file bug reports via [GitHub
Issues](http://github.com/omniti-labs/pg_amqp/issues/).

Authors
------

[Theo Schlossnagle](http://lethargy.org/~jesus/)
[Keith Fiske](http://www.keithf4.com)
