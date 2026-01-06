#!/bin/bash
# Generate self-signed SSL certificates for RabbitMQ testing
# Usage: ./generate_certs.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="$SCRIPT_DIR/certs"

# Create certs directory
mkdir -p "$CERTS_DIR"
cd "$CERTS_DIR"

echo "Generating SSL certificates for RabbitMQ testing..."

# Generate CA key and certificate
echo "Creating CA certificate..."
openssl genrsa -out ca.key 2048
openssl req -new -x509 -days 365 -key ca.key -out ca.crt \
    -subj "/C=US/ST=Test/L=Test/O=pg_amqp/CN=pg_amqp-test-ca"

# Generate server key and certificate signing request
echo "Creating server certificate..."
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
    -subj "/C=US/ST=Test/L=Test/O=pg_amqp/CN=localhost"

# Create server certificate extensions file
cat > server.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = rabbitmq
DNS.3 = rabbitmq-ssl
IP.1 = 127.0.0.1
EOF

# Sign server certificate with CA
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 365 -extfile server.ext

# Generate client key and certificate (optional, for mutual TLS testing)
echo "Creating client certificate..."
openssl genrsa -out client.key 2048
openssl req -new -key client.key -out client.csr \
    -subj "/C=US/ST=Test/L=Test/O=pg_amqp/CN=pg_amqp-client"

# Create client certificate extensions file
cat > client.ext << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
EOF

# Sign client certificate with CA
openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out client.crt -days 365 -extfile client.ext

# Clean up CSR and extension files
rm -f *.csr *.ext *.srl

# Set permissions - keys need to be world-readable for Docker containers
# (This is acceptable for test certificates only, NOT for production!)
chmod 644 *.crt
chmod 644 *.key

echo ""
echo "SSL certificates generated successfully in $CERTS_DIR:"
ls -la "$CERTS_DIR"
echo ""
echo "Files:"
echo "  ca.crt      - CA certificate (use for ssl_cacert)"
echo "  ca.key      - CA private key"
echo "  server.crt  - Server certificate"
echo "  server.key  - Server private key"
echo "  client.crt  - Client certificate (for mutual TLS)"
echo "  client.key  - Client private key (for mutual TLS)"
