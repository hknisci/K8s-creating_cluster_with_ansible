#!/usr/bin/env bash
set -euo pipefail

# Local testing script - runs the app in Docker and tests endpoints
# Prerequisites: docker, curl

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_DIR="${REPO_ROOT}/apps/nodejs-express"
IMAGE_NAME="nodejs-express-local:test"
CONTAINER_NAME="nodejs-express-test"
PORT=3000

cleanup() {
  echo "Cleaning up..."
  docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
}
trap cleanup EXIT

echo "=== Building Docker image ==="
docker build -t "${IMAGE_NAME}" "${APP_DIR}/"

echo ""
echo "=== Starting container ==="
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p "${PORT}:3000" \
  -e NODE_ENV=development \
  -e LOG_LEVEL=debug \
  "${IMAGE_NAME}"

echo "Waiting for container to be ready..."
for i in $(seq 1 10); do
  if curl -sf "http://localhost:${PORT}/health/live" &>/dev/null; then
    echo "Container is ready (attempt ${i})"
    break
  fi
  echo "  Waiting... (${i}/10)"
  sleep 2
done

echo ""
echo "=== Testing endpoints ==="

test_endpoint() {
  local path="$1"
  local expected_status="${2:-200}"
  local response
  local status

  status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PORT}${path}")
  if [[ "$status" == "$expected_status" ]]; then
    echo "  PASS  GET ${path} => HTTP ${status}"
  else
    echo "  FAIL  GET ${path} => HTTP ${status} (expected ${expected_status})"
    return 1
  fi
}

test_endpoint "/health/live"
test_endpoint "/health/ready"
test_endpoint "/"
test_endpoint "/metrics"

echo ""
echo "=== Sample responses ==="
echo "--- / ---"
curl -s "http://localhost:${PORT}/" | python3 -m json.tool 2>/dev/null || curl -s "http://localhost:${PORT}/"

echo ""
echo "--- /health/ready ---"
curl -s "http://localhost:${PORT}/health/ready" | python3 -m json.tool 2>/dev/null || true

echo ""
echo "=== All tests passed ==="
echo "Container is running. Access: http://localhost:${PORT}"
echo "Press Ctrl+C to stop."

# Keep alive for manual inspection
docker logs -f "${CONTAINER_NAME}"
