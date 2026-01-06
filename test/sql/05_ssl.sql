-- Test: SSL/TLS connection handling
-- These tests verify SSL configuration and connection behavior

-- Test 1: SSL broker configuration with all options
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_cacert, ssl_verify_peer, ssl_verify_hostname)
VALUES ('ssl-broker.example.com', 5671, '/secure', 'ssluser', 'sslpass', true, '/path/to/ca-bundle.crt', true, true)
RETURNING broker_id, host, port, ssl, ssl_cacert, ssl_verify_peer, ssl_verify_hostname;

-- Test 2: SSL broker with verification disabled (useful for self-signed certs)
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_verify_peer, ssl_verify_hostname)
VALUES ('self-signed.example.com', 5671, '/', 'admin', 'admin', true, false, false)
RETURNING broker_id, host, port, ssl, ssl_verify_peer, ssl_verify_hostname;

-- Test 3: SSL broker with peer verification only (hostname check disabled)
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl, ssl_verify_peer, ssl_verify_hostname)
VALUES ('partial-verify.example.com', 5671, '/', 'user', 'pass', true, true, false)
RETURNING broker_id, host, port, ssl, ssl_verify_peer, ssl_verify_hostname;

-- Test 4: SSL broker without explicit CA cert (uses system defaults)
INSERT INTO amqp.broker (host, port, vhost, username, password, ssl)
VALUES ('system-ca.example.com', 5671, '/', 'user', 'pass', true)
RETURNING broker_id, host, port, ssl, ssl_cacert, ssl_verify_peer, ssl_verify_hostname;

-- Verify all SSL configurations were stored correctly
SELECT broker_id, host, port, ssl, ssl_cacert, ssl_verify_peer, ssl_verify_hostname
FROM amqp.broker
WHERE ssl = true
ORDER BY broker_id;

-- Test 5: Attempt SSL connection to non-existent SSL broker
-- Should fail gracefully with appropriate SSL-related error
SELECT amqp.publish(1, 'test_exchange', 'test.key', 'SSL test message');

-- Test 6: Autonomous publish over SSL to non-existent broker
SELECT amqp.autonomous_publish(1, 'test_exchange', 'test.key', 'SSL autonomous message');

-- Test 7: Exchange declare over SSL to non-existent broker
SELECT amqp.exchange_declare(1, 'test_exchange', 'direct', false, true, false);

-- Test 8: Disconnect from SSL broker (should handle gracefully even if not connected)
SELECT amqp.disconnect(1);

-- Test 9: SSL with verification disabled - connection attempt
-- This broker has ssl_verify_peer and ssl_verify_hostname set to false
SELECT amqp.publish(2, 'test_exchange', 'test.key', 'Message with disabled SSL verification');

-- Test 10: Update SSL configuration
UPDATE amqp.broker
SET ssl_cacert = '/etc/ssl/certs/new-ca.crt', ssl_verify_peer = true
WHERE broker_id = 2;
SELECT broker_id, host, ssl_cacert, ssl_verify_peer FROM amqp.broker WHERE broker_id = 2;

-- Test 11: Toggle SSL on/off for a broker
UPDATE amqp.broker SET ssl = false WHERE broker_id = 2;
SELECT broker_id, host, ssl FROM amqp.broker WHERE broker_id = 2;

UPDATE amqp.broker SET ssl = true WHERE broker_id = 2;
SELECT broker_id, host, ssl FROM amqp.broker WHERE broker_id = 2;

-- Clean up
DELETE FROM amqp.broker;
SELECT setval('amqp.broker_broker_id_seq', 1, false);
