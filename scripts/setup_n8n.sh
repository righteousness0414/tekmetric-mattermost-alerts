#!/usr/bin/env bash
# setup_n8n.sh — import the workflow into n8n and activate it.
#
# Uses the n8n CLI inside the running container. After activation we restart
# n8n so the ACTIVE production webhook (/webhook/tekmetric) is registered and
# fire.sh can hit it without anyone clicking "Execute" in the UI.
set -uo pipefail

CONTAINER="${N8N_CONTAINER:-tmm-n8n}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_FILE="$SCRIPT_DIR/../workflow/tekmetric-mattermost.json"
WF_NAME="Tekmetric → Mattermost alerts (PoC)"

echo "→ copying workflow into container"
docker cp "$WF_FILE" "$CONTAINER:/tmp/wf.json"

echo "→ importing workflow"
docker exec "$CONTAINER" n8n import:workflow --input=/tmp/wf.json

echo "→ resolving workflow id"
WF_ID=$(docker exec "$CONTAINER" n8n list:workflow 2>/dev/null \
  | awk -F'|' -v n="$WF_NAME" '$2==n {print $1; exit}')
if [ -z "$WF_ID" ]; then
  # fallback: take the most recently listed id
  WF_ID=$(docker exec "$CONTAINER" n8n list:workflow 2>/dev/null | head -1 | cut -d'|' -f1)
fi
echo "  workflow id = $WF_ID"

echo "→ activating workflow"
docker exec "$CONTAINER" n8n update:workflow --id="$WF_ID" --active=true

echo "→ restarting n8n so the active webhook registers"
docker restart "$CONTAINER" >/dev/null

echo "✓ n8n workflow imported and active."
echo "  Production webhook: http://localhost:5678/webhook/tekmetric"
