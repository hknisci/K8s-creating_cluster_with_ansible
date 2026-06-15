#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="webhook-system"
SERVICE="resource-webhook"
SECRET_NAME="resource-webhook-tls"

echo "Generating TLS certificates for webhook..."

# Create temp directory
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

# Generate CA key and certificate
openssl genrsa -out "${TMPDIR}/ca.key" 4096
openssl req -new -x509 -days 3650 -key "${TMPDIR}/ca.key" \
    -subj "/CN=webhook-ca/O=DreamGames" \
    -out "${TMPDIR}/ca.crt"

# Generate server key and CSR
openssl genrsa -out "${TMPDIR}/server.key" 2048
openssl req -new -key "${TMPDIR}/server.key" \
    -subj "/CN=${SERVICE}.${NAMESPACE}.svc/O=DreamGames" \
    -out "${TMPDIR}/server.csr"

# Sign server cert with CA
cat > "${TMPDIR}/server-ext.cnf" <<EOF
subjectAltName = DNS:${SERVICE},DNS:${SERVICE}.${NAMESPACE},DNS:${SERVICE}.${NAMESPACE}.svc,DNS:${SERVICE}.${NAMESPACE}.svc.cluster.local
EOF

openssl x509 -req -days 3650 \
    -in "${TMPDIR}/server.csr" \
    -CA "${TMPDIR}/ca.crt" \
    -CAkey "${TMPDIR}/ca.key" \
    -CAcreateserial \
    -extfile "${TMPDIR}/server-ext.cnf" \
    -out "${TMPDIR}/server.crt"

# Create Kubernetes Secret
kubectl create secret tls "${SECRET_NAME}" \
    --cert="${TMPDIR}/server.crt" \
    --key="${TMPDIR}/server.key" \
    -n "${NAMESPACE}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Patch webhook config with CA bundle
CA_BUNDLE=$(base64 < "${TMPDIR}/ca.crt" | tr -d '\n')
kubectl patch validatingwebhookconfiguration resource-requests-webhook \
    --type='json' \
    -p="[{\"op\":\"replace\",\"path\":\"/webhooks/0/clientConfig/caBundle\",\"value\":\"${CA_BUNDLE}\"}]"

echo "TLS certificates generated and applied successfully."
echo "CA bundle (base64): ${CA_BUNDLE}"
