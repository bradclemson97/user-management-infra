#!/usr/bin/env bash
# Deletes all users from all data stores (UMS postgres, ACM postgres, Keycloak)
# except the bootstrap superuser (a0000000-0000-0000-0000-000000000001 / superuser@system.local).
#
# Usage:
#   ./scripts/reset-users.sh              # uses defaults (local docker setup)
#   KC_ADMIN=admin KC_ADMIN_PASSWORD=secret ./scripts/reset-users.sh

set -euo pipefail

SUPERUSER_UUID="a0000000-0000-0000-0000-000000000001"
SUPERUSER_EMAIL="superuser@system.local"
KC_REALM="${KC_REALM:-system}"
KC_CONTAINER="${KC_CONTAINER:-keycloak}"
KC_ADMIN="${KC_ADMIN:-admin}"
KC_ADMIN_PASSWORD="${KC_ADMIN_PASSWORD:-admin}"
KC_URL="${KC_URL:-http://localhost:8080}"
DB_CONTAINER="${DB_CONTAINER:-userdb}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${DB_NAME:-userdb}"

# ── Keycloak ──────────────────────────────────────────────────────────────────
echo "==> Authenticating with Keycloak..."
docker exec "$KC_CONTAINER" \
  /opt/keycloak/bin/kcadm.sh config credentials \
  --server "$KC_URL" --realm master \
  --user "$KC_ADMIN" --password "$KC_ADMIN_PASSWORD"

echo "==> Fetching Keycloak users in realm '$KC_REALM'..."
KC_USERS_JSON=$(docker exec "$KC_CONTAINER" \
  /opt/keycloak/bin/kcadm.sh get users -r "$KC_REALM" --fields id,username --limit 1000)

# Parse IDs excluding the superuser email
KC_IDS=$(echo "$KC_USERS_JSON" \
  | grep -v "$SUPERUSER_EMAIL" \
  | grep '"id"' \
  | sed 's/.*"id" : "\([^"]*\)".*/\1/')

if [ -z "$KC_IDS" ]; then
  echo "==> No Keycloak users to delete (superuser only)."
else
  for id in $KC_IDS; do
    echo "    Deleting Keycloak user $id..."
    docker exec "$KC_CONTAINER" \
      /opt/keycloak/bin/kcadm.sh delete "users/$id" -r "$KC_REALM"
  done
  echo "==> Keycloak users deleted."
fi

# ── Postgres (UMS + ACM) ──────────────────────────────────────────────────────
echo "==> Deleting non-superuser records from postgres..."
docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -v superuser="$SUPERUSER_UUID" <<'SQL'
BEGIN;

-- History tables must be cleared before the live tables to avoid FK issues
-- and to remove any audit records that were written when rows were previously deleted.
DELETE FROM user_management.users_history
WHERE system_user_id::text != :'superuser';

DELETE FROM user_management.user_details_history
WHERE usr_id IN (
  SELECT usr_id FROM user_management.users
  WHERE system_user_id::text != :'superuser'
);

DELETE FROM access_control.user_roles_history
WHERE usr_id IN (
  SELECT usr_id FROM access_control.users
  WHERE system_user_id::text != :'superuser'
);

-- Now delete the live records (triggers will fire but history has already been cleared)
DELETE FROM user_management.user_details
WHERE usr_id IN (
  SELECT usr_id FROM user_management.users
  WHERE system_user_id::text != :'superuser'
);

DELETE FROM user_management.users
WHERE system_user_id::text != :'superuser';

DELETE FROM access_control.user_roles
WHERE usr_id IN (
  SELECT usr_id FROM access_control.users
  WHERE system_user_id::text != :'superuser'
);

DELETE FROM access_control.users
WHERE system_user_id::text != :'superuser';

COMMIT;
SQL

echo "==> Postgres records deleted."

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "==> Verification:"
docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c \
  "SELECT 'UMS' AS store, COUNT(*) AS remaining_users FROM user_management.users
   UNION ALL
   SELECT 'ACM', COUNT(*) FROM access_control.users;"
echo "    Keycloak users remaining:"
docker exec "$KC_CONTAINER" \
  /opt/keycloak/bin/kcadm.sh get users -r "$KC_REALM" --fields username
