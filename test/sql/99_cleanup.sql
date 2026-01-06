-- Test: Extension cleanup and recreation
-- Verifies that the extension can be dropped and recreated cleanly

-- Ensure extension exists
SELECT extname FROM pg_extension WHERE extname = 'amqp';

-- Drop the extension
DROP EXTENSION amqp;

-- Verify extension is gone
SELECT extname FROM pg_extension WHERE extname = 'amqp';

-- Verify schema is gone
SELECT nspname FROM pg_namespace WHERE nspname = 'amqp';

-- Recreate the extension
CREATE EXTENSION amqp;

-- Verify extension is back
SELECT extname, extversion FROM pg_extension WHERE extname = 'amqp';

-- Verify schema is back
SELECT nspname FROM pg_namespace WHERE nspname = 'amqp';

-- Final cleanup
DROP EXTENSION amqp;
