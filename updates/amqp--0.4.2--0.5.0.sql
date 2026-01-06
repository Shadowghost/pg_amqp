-- Upgrade pg_amqp from 0.4.2 to 0.5.0
-- This version upgrades librabbitmq to 0.15.0 and adds SSL/TLS support

-- Add SSL configuration columns to broker table
ALTER TABLE @extschema@.broker
  ADD COLUMN IF NOT EXISTS ssl boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS ssl_cacert text,
  ADD COLUMN IF NOT EXISTS ssl_verify_peer boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS ssl_verify_hostname boolean DEFAULT true;

COMMENT ON COLUMN @extschema@.broker.ssl IS 'Enable SSL/TLS connection to broker';
COMMENT ON COLUMN @extschema@.broker.ssl_cacert IS 'Path to CA certificate file for SSL verification';
COMMENT ON COLUMN @extschema@.broker.ssl_verify_peer IS 'Verify server certificate (default: true)';
COMMENT ON COLUMN @extschema@.broker.ssl_verify_hostname IS 'Verify server hostname matches certificate (default: true)';
