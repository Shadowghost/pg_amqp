-- Test: Error handling without a broker
-- These tests verify that the extension handles errors gracefully
-- when no broker is available or configured incorrectly

-- Set up a broker that doesn't exist (connection will fail)
INSERT INTO amqp.broker (host, port, vhost, username, password)
VALUES ('nonexistent.host.invalid', 5672, '/', 'guest', 'guest');

-- Test publish to non-existent broker (should fail gracefully)
-- The function returns false when it cannot connect
SELECT amqp.publish(1, 'test_exchange', 'test.routing.key', 'test message');

-- Test autonomous_publish to non-existent broker
SELECT amqp.autonomous_publish(1, 'test_exchange', 'test.routing.key', 'test message');

-- Test exchange_declare to non-existent broker
SELECT amqp.exchange_declare(1, 'test_exchange', 'direct', false, true, false);

-- Test disconnect on non-connected broker (should not error)
SELECT amqp.disconnect(1);

-- Test with invalid broker_id (not in table)
-- These should return false or handle gracefully
SELECT amqp.publish(999, 'test_exchange', 'test.routing.key', 'test message');
SELECT amqp.autonomous_publish(999, 'test_exchange', 'test.routing.key', 'test message');
SELECT amqp.exchange_declare(999, 'test_exchange', 'direct', false, true, false);

-- Clean up
DELETE FROM amqp.broker;
SELECT setval('amqp.broker_broker_id_seq', 1, false);
