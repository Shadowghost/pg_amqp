-- Test: Extension creation and basic schema validation
-- This test verifies that the pg_amqp extension can be created
-- and sets up the expected schema and objects.

-- Create the extension
CREATE EXTENSION amqp;

-- Verify extension exists
SELECT extname, extversion FROM pg_extension WHERE extname = 'amqp';

-- Verify schema exists
SELECT nspname FROM pg_namespace WHERE nspname = 'amqp';

-- Verify broker table exists with correct columns
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'amqp' AND table_name = 'broker'
ORDER BY ordinal_position;

-- Verify primary key constraint (filter out auto-generated NOT NULL constraints from PG16+)
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'amqp' AND table_name = 'broker'
  AND constraint_name NOT LIKE '%_not_null'
ORDER BY constraint_name;
