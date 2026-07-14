#!/usr/bin/env bash
# Statusline script that ALSO mirrors subscription usage for the factory gate.
#
# Claude Code pipes a JSON payload to the statusline on every update; for
# claude.ai Pro/Max logins it includes rate_limits.{five_hour,seven_day}
# .used_percentage / .resets_at — the official way to watch your remaining
# allowance (see code.claude.com/docs/en/statusline.md and errors.md). This
# script renders a one-line status AND writes those fields to
# .agentic/usage.json, which scripts/lib/usage_gate.sh reads before the
# factory claims any work.
#
# Install (per project, after /agentic-loop:init):
#   1. chmod +x scripts/statusline-usage.sh   (init copies it there)
#   2. In .claude/settings.json:
#        {"statusLine": {"type": "command", "command": "scripts/statusline-usage.sh"}}
# Notes:
#   - rate_limits appears only after the first API response of a session and
#     each window may be independently absent; the gate fails open on staleness.
#   - The mirror only updates while a session is LIVE (statusline fires after
#     each assistant turn / on refreshInterval) — which is exactly the factory
#     day-mode setup: the looping session keeps its own mirror fresh.

set -euo pipefail

payload="$(cat)"

usage_file="${FACTORY_USAGE_FILE:-.agentic/usage.json}"

if command -v jq >/dev/null 2>&1; then
  mkdir -p "$(dirname "$usage_file")"
  echo "$payload" | jq --argjson now "$(date +%s)" \
    '{mirrored_at: $now, rate_limits: (.rate_limits // {})}' \
    > "${usage_file}.tmp" 2>/dev/null \
    && mv "${usage_file}.tmp" "$usage_file" \
    || rm -f "${usage_file}.tmp"

  model="$(echo "$payload" | jq -r '.model.display_name // "claude"')"
  dir="$(echo "$payload" | jq -r '.workspace.current_dir // "."' )"
  h5="$(echo "$payload" | jq -r '.rate_limits.five_hour.used_percentage // empty')"
  d7="$(echo "$payload" | jq -r '.rate_limits.seven_day.used_percentage // empty')"

  line="${model} | ${dir##*/}"
  [[ -n "$h5" ]] && line+=" | 5h:${h5}%"
  [[ -n "$d7" ]] && line+=" | 7d:${d7}%"
  printf '%s' "$line"
else
  printf 'claude (install jq for usage gating)'
fi
