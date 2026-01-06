pg_amqp
=============

The pg_amqp package provides the ability for postgres statements to directly
publish messages to an [AMQP](http://www.amqp.org/) broker.

All bug reports, feature requests and general questions can be directed to the Issues section on Github. - http://github.com/omniti-labs/pg_amqp


Building
--------

### Prerequisites

- PostgreSQL 9.1+ development headers (`postgresql-server-dev-XX` or similar)
- OpenSSL development libraries (`libssl-dev` or `openssl-devel`)
- curl (for downloading librabbitmq during build)
- pkg-config

### Standard Build

To build pg_amqp, just do this:

    make
    make install

The build process automatically downloads librabbitmq 0.15.0 from GitHub during the first build.

### Docker Build

A Dockerfile is provided for containerized builds:

    # Build with default PostgreSQL 17
    docker build -t pg_amqp-builder .
    docker run --rm -v "$(pwd)":/build pg_amqp-builder make

    # Build for a specific PostgreSQL version (14, 15, 16, 17)
    docker build --build-arg PG_VERSION=16 -t pg_amqp-builder:pg16 .
    docker run --rm -v "$(pwd)":/build pg_amqp-builder:pg16 make

Testing
-------

### Test Categories

- **Basic tests**: No external dependencies, test extension loading and configuration
- **Integration tests**: Require RabbitMQ on port 5672
- **SSL integration tests**: Require RabbitMQ with SSL on port 5671

### Using the Test Runner

The `test/run_tests.sh` script provides a convenient way to run tests:

    # Run basic tests only (no RabbitMQ required)
    ./test/run_tests.sh --basic

    # Run all tests with automatic RabbitMQ management
    ./test/run_tests.sh --start-rabbitmq --stop-rabbitmq --all

    # Run SSL integration tests only
    ./test/run_tests.sh --start-rabbitmq --ssl

    # Run with specific PostgreSQL version
    ./test/run_tests.sh --pg-config /usr/lib/postgresql/17/bin/pg_config --all

### Using Docker Compose

Docker Compose provides RabbitMQ with SSL support enabled:

    # Generate SSL certificates (first time only)
    ./test/ssl/generate_certs.sh

    # Start RabbitMQ with SSL support
    docker compose up -d rabbitmq

    # Start RabbitMQ and PostgreSQL
    docker compose up -d rabbitmq postgres

    # Run containerized integration tests
    docker compose up --build --abort-on-container-exit test

    # Stop services
    docker compose down

**Ports:**
- 5672: AMQP (non-SSL)
- 5671: AMQP over SSL/TLS
- 15672: RabbitMQ Management UI (guest/guest)

### Running Tests with Make

    # Basic tests (no RabbitMQ required)
    make test

    # Integration tests (requires RabbitMQ at localhost:5672)
    make test-integration

    # SSL integration tests (requires RabbitMQ with SSL at localhost:5671)
    make test-ssl

    # All tests
    make test-all

### Troubleshooting

If you encounter an error such as:

    "Makefile", line 8: Need an operator

You need to use GNU make, which may well be installed on your system as
`gmake`:

    gmake
    gmake install

If you encounter an error such as:

    make: pg_config: Command not found

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

    env PG_CONFIG=/path/to/pg_config make && make install

Some prepackaged Mac installs of postgres might need a little coaxing with
modern XCodes.  If you encounter an error such as:

    make: /Applications/Xcode.app/Contents/Developer/Toolchains/OSX10.8.xctoolchain/usr/bin/cc: No such file or directory

Then you'll need to link the toolchain

    sudo ln -s /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain /Applications/Xcode.app/Contents/Developer/Toolchains/OSX10.8.xctoolchain

And if you encounter an error about a missing `/usr/bin/postgres`:

    ld: file not found: /usr/bin/postgres

You might need to link in your real postgres:

    sudo ln -s /usr/bin/postgres_real /usr/bin/postgres

Loading
-------

Once amqp is installed, you can add it to a database. Add this line to your
postgresql config

    shared_preload_libraries = 'pg_amqp.so'

This extension requires PostgreSQL 9.1.0 or greater, so loading amqp is as simple
as connecting to a database as a super user and running

    CREATE EXTENSION amqp;

If you've upgraded your cluster to PostgreSQL 9.1 and already had amqp
installed, you can upgrade it to a properly packaged extension with:

    CREATE EXTENSION amqp FROM unpackaged;

This is required to update to any versions >= 0.4.0.

To update to the latest version, run the following command after running "make install" again:

    ALTER EXTENSION amqp UPDATE;

Basic Usage
-----------

Insert AMQP broker information (host/port/user/pass) into the
`amqp.broker` table.

A process starts and connects to PostgreSQL and runs:

    SELECT amqp.publish(broker_id, 'amqp.direct', 'foo', 'message');

Upon process termination, all broker connections will be torn down.
If there is a need to disconnect from a specific broker, one can call:

    select amqp.disconnect(broker_id);

which will disconnect from the broker if it is connected and do nothing
if it is already disconnected.

SSL/TLS Connections
-------------------

To connect to an AMQP broker using SSL/TLS, configure the broker entry with
the SSL options:

    INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_verify_peer, ssl_verify_hostname)
    VALUES ('rabbitmq.example.com', 5671, '/', 'user', 'pass', true, true, true);

The SSL-related columns are:

- `ssl` (boolean): Enable SSL/TLS connection (default: false)
- `ssl_cacert` (text): Path to CA certificate file for server verification
- `ssl_verify_peer` (boolean): Verify the server's certificate (default: true)
- `ssl_verify_hostname` (boolean): Verify the server's hostname matches the certificate (default: true)

For self-signed certificates or internal CAs, specify the CA certificate path:

    INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_cacert)
    VALUES ('rabbitmq.example.com', 5671, '/', 'user', 'pass', true, '/etc/ssl/certs/ca-certificates.crt');

