#!/usr/bin/env bash
# Usage gate for factory loops: postpone work when subscription usage is high.
#
# Data source: .agentic/usage.json, mirrored from the statusline payload's
# rate_limits fields by templates/statusline-usage.sh (the only authoritative
# programmatic %-of-cap source Anthropic exposes — /usage is TUI-only, OTEL has
# token counts but no cap %, community JSONL parsers only estimate the cap).
#
# Expected file shape (fields may be independently absent, per the docs):
#   { "mirrored_at": <epoch>,
#     "rate_limits": {
#       "five_hour": {"used_percentage": N, "resets_at": <epoch>},
#       "seven_day": {"used_percentage": N, "resets_at": <epoch>} } }
#
# Policy:
#   - If any window's used_percentage >= FACTORY_USAGE_THRESHOLD (default 90),
#     the gate says POSTPONE and prints {"gate":"postpone", ...} with the
#     latest resets_at among the windows over threshold (waiting for the
#     earlier one alone would still leave the other capped).
#   - Missing or stale file (older than FACTORY_USAGE_STALE_MINUTES, default
#     120): FAIL OPEN with a stderr warning — a broken statusline must not
#     deadlock the factory. The hard cap error remains the final backstop.
#
# CLI:
#   usage_gate.sh check   exit 0 = proceed; exit 5 = postpone (JSON on stdout)

set -euo pipefail

# Opt-in observability (no-op unless enabled — see obs.sh).
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/obs.sh"

USAGE_FILE="${FACTORY_USAGE_FILE:-.agentic/usage.json}"
THRESHOLD="${FACTORY_USAGE_THRESHOLD:-90}"
STALE_MINUTES="${FACTORY_USAGE_STALE_MINUTES:-120}"

command -v jq >/dev/null 2>&1 || { echo "usage_gate: jq not found" >&2; exit 3; }

usage_gate_check() {
  if [[ ! -f "$USAGE_FILE" ]]; then
    echo "usage_gate: $USAGE_FILE not found — failing open (install templates/statusline-usage.sh to enable gating)" >&2
    return 0
  fi

  local now mirrored_at age_min
  now="$(date +%s)"
  mirrored_at="$(jq -r '.mirrored_at // 0' "$USAGE_FILE" 2>/dev/null || echo 0)"
  if ! [[ "$mirrored_at" =~ ^[0-9]+$ ]] || [[ "$mirrored_at" -eq 0 ]]; then
    echo "usage_gate: $USAGE_FILE has no mirrored_at — failing open" >&2
    return 0
  fi
  age_min=$(( (now - mirrored_at) / 60 ))
  if [[ $age_min -gt $STALE_MINUTES ]]; then
    echo "usage_gate: $USAGE_FILE is ${age_min}min old (> ${STALE_MINUTES}min) — failing open" >&2
    return 0
  fi

  # Postpone until the LATEST reset among windows at/over threshold.
  local verdict
  verdict="$(jq --argjson t "$THRESHOLD" '
    [ .rate_limits // {}
      | to_entries[]
      | select(.value.used_percentage != null)
      | select(.value.used_percentage >= $t)
      | {window: .key,
         used: .value.used_percentage,
         resets_at: (.value.resets_at // 0)} ]
    | if length == 0 then {gate: "proceed"}
      else {gate: "postpone",
            over: .,
            resets_at: (map(.resets_at) | max)}
      end
  ' "$USAGE_FILE")"

  if [[ "$(echo "$verdict" | jq -r '.gate')" == "postpone" ]]; then
    obs_event gate tracker "$(echo "$verdict" | jq -c '
      {status: "postponed",
       detail: {verdict: "postpone", windows_over: (.over // []),
                resets_at: (.resets_at // null)}}' 2>/dev/null || echo '{}')"
    echo "$verdict"
    return 5
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-check}" in
    check) usage_gate_check ;;
    *) echo "usage: usage_gate.sh check" >&2; exit 2 ;;
  esac
fi
