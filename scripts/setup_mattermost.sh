#!/usr/bin/env bash
# setup_mattermost.sh — fully automate Mattermost first-run setup via REST API.
#
# Creates: admin user -> team -> #shop-floor channel -> ONE incoming webhook.
# Writes the webhook URL (reachable from the n8n container) into ./.env as
# MATTERMOST_WEBHOOK_URL, which docker-compose feeds to the n8n service.
#
# No UI clicks required. Re-runnable: if pieces already exist it reuses them.
set -uo pipefail

MM_HOST="${MM_HOST:-http://localhost:8065}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-Admin12345!}"
TEAM_NAME="main"
TEAM_DISPLAY="Main St Auto"
CHANNEL_NAME="shop-floor"
CHANNEL_DISPLAY="Shop Floor"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

jget() { python3 -c "import sys,json;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null; }

echo "→ waiting for Mattermost to be ready at $MM_HOST ..."
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$MM_HOST/api/v4/system/ping" || true)
  [ "$code" = "200" ] && { echo "  ready (after ${i} tries)"; break; }
  sleep 3
  [ "$i" = "60" ] && { echo "✗ Mattermost did not become ready"; exit 1; }
done

# 1. Create first user (becomes system admin automatically when DB is empty).
echo "→ creating admin user ($ADMIN_USER)"
curl -s -X POST "$MM_HOST/api/v4/users" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"$ADMIN_EMAIL\",\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" >/dev/null

# 2. Login, capture session token from the response header.
echo "→ logging in"
TOKEN=$(curl -s -D - -o /dev/null -X POST "$MM_HOST/api/v4/users/login" \
  -H 'Content-Type: application/json' \
  -d "{\"login_id\":\"$ADMIN_EMAIL\",\"password\":\"$ADMIN_PASS\"}" \
  | awk 'tolower($1)=="token:"{print $2}' | tr -d '\r')
if [ -z "$TOKEN" ]; then echo "✗ login failed"; exit 1; fi
AUTH="Authorization: Bearer $TOKEN"

# 2b. Enable incoming webhooks + username/icon override, so the bot can post as
#     "Tekmetric Bot" with a wrench icon (off by default in the preview image).
echo "→ enabling incoming webhooks + username/icon override"
curl -s "$MM_HOST/api/v4/config" -H "$AUTH" | python3 -c "
import sys, json
cfg = json.load(sys.stdin)
cfg['ServiceSettings']['EnableIncomingWebhooks'] = True
cfg['ServiceSettings']['EnablePostUsernameOverride'] = True
cfg['ServiceSettings']['EnablePostIconOverride'] = True
json.dump(cfg, open('/tmp/mm_cfg.json','w'))
"
curl -s -X PUT "$MM_HOST/api/v4/config" -H "$AUTH" -H 'Content-Type: application/json' \
  --data @/tmp/mm_cfg.json >/dev/null

# 3. Create (or fetch) the team.
echo "→ creating team ($TEAM_NAME)"
TEAM_ID=$(curl -s -X POST "$MM_HOST/api/v4/teams" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$TEAM_NAME\",\"display_name\":\"$TEAM_DISPLAY\",\"type\":\"O\"}" | jget id)
if [ -z "$TEAM_ID" ]; then
  TEAM_ID=$(curl -s "$MM_HOST/api/v4/teams/name/$TEAM_NAME" -H "$AUTH" | jget id)
fi
echo "  team_id=$TEAM_ID"

# 4. Create (or fetch) the channel.
echo "→ creating channel (#$CHANNEL_NAME)"
CHANNEL_ID=$(curl -s -X POST "$MM_HOST/api/v4/channels" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"team_id\":\"$TEAM_ID\",\"name\":\"$CHANNEL_NAME\",\"display_name\":\"$CHANNEL_DISPLAY\",\"type\":\"O\"}" | jget id)
if [ -z "$CHANNEL_ID" ]; then
  CHANNEL_ID=$(curl -s "$MM_HOST/api/v4/teams/$TEAM_ID/channels/name/$CHANNEL_NAME" -H "$AUTH" | jget id)
fi
echo "  channel_id=$CHANNEL_ID"

# 5. Create the incoming webhook.
echo "→ creating incoming webhook"
HOOK_ID=$(curl -s -X POST "$MM_HOST/api/v4/hooks/incoming" -H "$AUTH" -H 'Content-Type: application/json' \
  -d "{\"channel_id\":\"$CHANNEL_ID\",\"display_name\":\"Tekmetric Bot\"}" | jget id)
if [ -z "$HOOK_ID" ]; then echo "✗ webhook creation failed"; exit 1; fi

# 6. Write the URL n8n must use. n8n is a sibling container, so it reaches
#    Mattermost via the compose service name "mattermost", NOT localhost.
INTERNAL_URL="http://mattermost:8065/hooks/$HOOK_ID"
HOST_URL="$MM_HOST/hooks/$HOOK_ID"
echo "MATTERMOST_WEBHOOK_URL=$INTERNAL_URL" > "$ENV_FILE"

echo
echo "✓ Mattermost ready."
echo "  Incoming webhook (host view):     $HOST_URL"
echo "  Incoming webhook (n8n container): $INTERNAL_URL"
echo "  Wrote $ENV_FILE"
