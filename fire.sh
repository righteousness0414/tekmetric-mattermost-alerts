#!/usr/bin/env bash
# fire.sh — fire ASSUMED Tekmetric webhook payloads at the local n8n endpoint.
#
#   ./fire.sh                      fire all 4 events in sequence (demo / screen recording)
#   ./fire.sh inspection_finished  fire a single event by name
#   ./fire.sh ro_status_changed_trivial   fire a trivial RO transition (should be FILTERED OUT)
#
# Each payload lives in sample_payloads/<event>.json.
set -euo pipefail

# n8n production webhook (workflow must be ACTIVE). Override with N8N_WEBHOOK_URL.
N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-http://localhost:5678/webhook/tekmetric}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD_DIR="$SCRIPT_DIR/sample_payloads"

fire() {
  local event="$1"
  local file="$PAYLOAD_DIR/$event.json"
  if [[ ! -f "$file" ]]; then
    echo "✗ no payload file: $file" >&2
    return 1
  fi
  echo "→ firing $event"
  curl -sS -X POST "$N8N_WEBHOOK_URL" \
    -H 'Content-Type: application/json' \
    -d @"$file"
  echo
}

# The 4 events in a natural shop-floor order (what the demo recording shows).
ALL_EVENTS=(ro_status_changed tech_note_added inspection_finished job_completed)

if [[ $# -ge 1 ]]; then
  fire "$1"
else
  for e in "${ALL_EVENTS[@]}"; do
    fire "$e"
    sleep 2   # ~2s gap so the 4 notifications appear one-by-one on screen
  done
  echo "✓ fired all ${#ALL_EVENTS[@]} events"
fi
