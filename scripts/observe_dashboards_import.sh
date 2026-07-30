#!/usr/bin/env bash
# observe_dashboards_import.sh — one-command import of the three prebuilt
# boards (Tonight / The Factory / Spec Economics) into a live OpenObserve.
#
# Plugin-root tool, like observe_dashboards_gen.py: dashboard setup happens
# ONCE per OpenObserve instance (the store, typically the always-on Mini),
# not once per project — so this is invoked directly from wherever the
# plugin lives, not scaffolded into a project's scripts/.
#
#   O2_URL=https://mini.<tailnet>.ts.net O2_AUTH=you@example.com:pass \
#     ./scripts/observe_dashboards_import.sh
#
#   --dry-run   list what would be created, touch nothing
#
# Re-running creates NEW dashboards each time (OpenObserve's create-by-POST
# has no upsert-by-title) — run once per instance; delete the old ones in
# the UI first if you're re-importing after an edit.
#
# Requires the same O2_URL/O2_AUTH as observe_push.sh (put them in ./.env
# or export them directly — this script has no project config to read,
# since it targets the store, not a project's event log).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASH_DIR="$SCRIPT_DIR/../templates/observability/dashboards"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

if [[ -z "${O2_URL:-}" || -z "${O2_AUTH:-}" ]]; then
  echo "observe_dashboards_import: set O2_URL and O2_AUTH (see templates/observability/README.md)" >&2
  exit 2
fi

O2_ORG="${O2_ORG:-default}"
ENDPOINT="${O2_URL%/}/api/$O2_ORG/dashboards"

shopt -s nullglob
FILES=("$DASH_DIR"/*.dashboard.json)
shopt -u nullglob
[[ ${#FILES[@]} -gt 0 ]] || { echo "observe_dashboards_import: no dashboard JSON under $DASH_DIR" >&2; exit 2; }

for f in "${FILES[@]}"; do
  TITLE="$(jq -r '.title' "$f")"
  if [[ $DRY -eq 1 ]]; then
    echo "would import: $TITLE ($(jq '.tabs[0].panels | length' "$f") panels) from $(basename "$f")"
    continue
  fi
  # < /dev/null: closes stdin so a held-open non-tty shell never hangs curl.
  RESP="$(curl -sf -X POST "$ENDPOINT" -u "$O2_AUTH" \
    -H 'Content-Type: application/json' --data-binary @"$f" < /dev/null)" \
    || { echo "observe_dashboards_import: failed to import $TITLE — check O2_URL/O2_AUTH" >&2; exit 1; }
  DID="$(jq -r '.v8.dashboardId // empty' <<<"$RESP")"
  if [[ -n "$DID" ]]; then
    echo "imported: $TITLE -> $DID"
  else
    echo "observe_dashboards_import: unexpected response for $TITLE: $RESP" >&2
    exit 1
  fi
done

[[ $DRY -eq 1 ]] || echo "done — open OpenObserve > Dashboards to view them."
