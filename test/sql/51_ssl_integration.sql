-- Test: SSL/TLS integration tests with RabbitMQ broker
-- These tests require a running RabbitMQ instance with SSL enabled at localhost:5671
-- with default guest/guest credentials

-- Create the extension first
CREATE EXTENSION amqp;

-- Set up SSL broker configuration
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_verify_peer, ssl_verify_hostname)
VALUES ('localhost', 5671, '/', 'guest', 'guest', true, false, false)
RETURNING broker_id, host, port, ssl;

-- Test: Declare an exchange over SSL
SELECT amqp.exchange_declare(1, 'pg_amqp_ssl_test_exchange', 'direct', false, false, true);

-- Test: Basic publish over SSL (transactional)
BEGIN;
SELECT amqp.publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.test.key', 'Hello from pg_amqp over SSL!');
COMMIT;

-- Test: Autonomous publish over SSL (immediate)
SELECT amqp.autonomous_publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.test.key', 'Autonomous SSL message');

-- Test: Publish with message properties over SSL
SELECT amqp.publish(
    1,
    'pg_amqp_ssl_test_exchange',
    'ssl.test.props',
    '{"secure": true}',
    2,                    -- delivery_mode (persistent)
    'application/json',   -- content_type
    'ssl.reply.queue',    -- reply_to
    'ssl-corr-123'        -- correlation_id
);

-- Test: Multiple publishes in a transaction over SSL
BEGIN;
SELECT amqp.publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.batch.1', 'SSL batch message 1');
SELECT amqp.publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.batch.2', 'SSL batch message 2');
SELECT amqp.publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.batch.3', 'SSL batch message 3');
COMMIT;

-- Test: Rollback should not publish messages over SSL
BEGIN;
SELECT amqp.publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.rollback.key', 'This should NOT be published');
ROLLBACK;

-- Test: Disconnect and reconnect over SSL
SELECT amqp.disconnect(1);
SELECT amqp.autonomous_publish(1, 'pg_amqp_ssl_test_exchange', 'ssl.reconnect.key', 'Message after SSL reconnect');

-- Clean up
SELECT amqp.disconnect(1);
DELETE FROM amqp.broker;
SELECT setval('amqp.broker_broker_id_seq', 1, false);

-- Report success
SELECT 'SSL integration tests completed successfully' as status;
