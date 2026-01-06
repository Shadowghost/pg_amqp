-- Test: Broker configuration table operations
-- Tests CRUD operations on the amqp.broker table

-- Insert a basic broker configuration (non-SSL)
INSERT INTO amqp.broker (host, port, vhost, username, password)
VALUES ('localhost', 5672, '/', 'guest', 'guest')
RETURNING broker_id, host, port, vhost, username, ssl;

-- Insert a broker with SSL configuration
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_cacert, ssl_verify_peer, ssl_verify_hostname)
VALUES ('secure.example.com', 5671, '/secure', 'admin', 'secret', true, '/etc/ssl/certs/ca-bundle.crt', true, true)
RETURNING broker_id, host, port, ssl, ssl_verify_peer, ssl_verify_hostname;

-- Insert broker with custom port and no SSL verification
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_verify_peer, ssl_verify_hostname)
VALUES ('test.internal', 5673, '/test', 'testuser', 'testpass', true, false, false)
RETURNING broker_id, host, port, ssl, ssl_verify_peer, ssl_verify_hostname;

-- Verify all brokers were created
SELECT broker_id, host, port, vhost, username, ssl, ssl_verify_peer, ssl_verify_hostname
FROM amqp.broker
ORDER BY broker_id;

-- Test update operation
UPDATE amqp.broker SET password = 'newpassword' WHERE broker_id = 1;
SELECT broker_id, host, password FROM amqp.broker WHERE broker_id = 1;

-- Test multi-host configuration (same broker_id different hosts for failover)
-- First delete existing broker_id 1 entry
DELETE FROM amqp.broker WHERE broker_id = 1;

-- Now we can insert multiple hosts (the serial will continue from where it left off)
INSERT INTO amqp.broker (host, port, vhost, username, password)
VALUES
    ('primary.rabbitmq.local', 5672, '/', 'guest', 'guest'),
    ('secondary.rabbitmq.local', 5672, '/', 'guest', 'guest');

-- Verify the entries
SELECT broker_id, host, port, vhost FROM amqp.broker ORDER BY broker_id, host;

-- Clean up for next tests
DELETE FROM amqp.broker;
SELECT setval('amqp.broker_broker_id_seq', 1, false);
