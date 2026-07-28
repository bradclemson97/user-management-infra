#!/bin/bash
# Deploy or update all services. Safe to re-run on updates.
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BASE_DIR="$(cd "${INFRA_DIR}/.." && pwd)"
ENV_FILE="${INFRA_DIR}/.env.prod"

if [ ! -f "${ENV_FILE}" ]; then
  echo "ERROR: ${ENV_FILE} not found. Copy .env.prod.example and fill in secrets."
  exit 1
fi

echo "=== Pulling latest source ==="
for repo in user-management-service access-control-manager keycloak-manager user-management-ui user-management-infra; do
  echo "  Updating ${repo}..."
  git -C "${BASE_DIR}/${repo}" pull --ff-only
done

echo "=== Building Docker images ==="
docker-compose \
  -f "${INFRA_DIR}/docker-compose.prod.yml" \
  --env-file "${ENV_FILE}" \
  build --parallel

echo "=== Starting services ==="
docker-compose \
  -f "${INFRA_DIR}/docker-compose.prod.yml" \
  --env-file "${ENV_FILE}" \
  up -d --remove-orphans

echo "=== Waiting for health checks ==="
sleep 10
docker-compose \
  -f "${INFRA_DIR}/docker-compose.prod.yml" \
  --env-file "${ENV_FILE}" \
  ps

echo "=== Deployment complete ==="
echo "App:      https://app.bradleyclemson.com"
echo "Keycloak: https://app.bradleyclemson.com/admin"
