# CLAUDE.md

This file gives Claude Code context for working in this repository.

## Project

**tekmetric-mattermost-alerts** — a service that receives events from
[Tekmetric](https://tekmetric.com/) and posts formatted alert notifications to
[Mattermost](https://mattermost.com/) channels.

## Status

Working **PoC** (verified end-to-end locally). Stack:

- **n8n** (Docker) — receives an HTTP webhook, normalizes the payload, branches
  on `event_type`, builds an emoji/colored message, POSTs to Mattermost.
- **Mattermost** (Docker, `mattermost-preview`) — destination chat, `#shop-floor`.
- `docker-compose.yml` runs both; `scripts/` automate setup; `fire.sh` fires
  sample events; `workflow/tekmetric-mattermost.json` is the importable workflow.

Payloads in `sample_payloads/` are an **ASSUMED schema** (not validated against
live Tekmetric). Going live = remap the single *Normalize / Map* node. See
`README.md` for full details and verification results.

## Conventions

- Keep secrets and external URLs in environment variables, never in source.
- Document operational/runbook notes alongside the code as the project grows.
