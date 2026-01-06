CREATE TABLE @extschema@.broker (
  broker_id serial NOT NULL,
  host text NOT NULL,
  port integer NOT NULL DEFAULT 5672,
  vhost text,
  username text,
  password text,
  ssl boolean DEFAULT false,
  ssl_cacert text,
  ssl_verify_peer boolean DEFAULT true,
  ssl_verify_hostname boolean DEFAULT true,
  PRIMARY KEY (broker_id, host, port)
);

COMMENT ON COLUMN @extschema@.broker.ssl IS 'Enable SSL/TLS connection to broker';
COMMENT ON COLUMN @extschema@.broker.ssl_cacert IS 'Path to CA certificate file for SSL verification';
COMMENT ON COLUMN @extschema@.broker.ssl_verify_peer IS 'Verify server certificate (default: true)';
COMMENT ON COLUMN @extschema@.broker.ssl_verify_hostname IS 'Verify server hostname matches certificate (default: true)';

SELECT pg_catalog.pg_extension_config_dump('@extschema@.broker', '');
SELECT pg_catalog.pg_extension_config_dump('@extschema@.broker_broker_id_seq', '');

