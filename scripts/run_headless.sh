#!/usr/bin/env bash
# run_headless.sh — GATED wrapper for unattended `claude -p` loop runs.
#
# ############################  BILLING WARNING  ##############################
# Billing follows the AUTH METHOD, not headless-vs-interactive (verified
# against official docs 2026-07-14, costs.md): plain `claude -p` under your
# OAuth subscription login draws the same Max allowance as interactive use;
# `--bare` mode skips OAuth and requires ANTHROPIC_API_KEY — per-token API
# billing; CI runners (GitHub Actions etc.) use API keys by design. The trap:
# a docs-recommended `--bare` flag, or any ANTHROPIC_API_KEY in scope, silently
# changes your meter. Policies stay volatile — verify your plan's current
# terms. This script refuses to run without --i-understand-billing.
# #############################################################################
#
# Loop discipline (Ralph-style):
#   - State lives in files, not in context: a PROMPT file re-read every
#     iteration, plus your repo/git as memory. One deliverable per iteration.
#   - Completion is decided by --check-cmd (e.g. your test suite), never by
#     the model claiming it is done.
#   - Hard caps: --max-iterations (default 5) and wall-clock via your shell.
#   - Escape hatch: if --check-cmd still fails after the final iteration, the
#     run exits non-zero so you notice.
#
# Usage:
#   ./scripts/run_headless.sh --i-understand-billing \
#       --prompt-file PROMPT.md --check-cmd "npm test" \
#       [--max-iterations 5] [--dry-run] [--yes]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Opt-in observability (no-op unless enabled — see lib/obs.sh).
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/obs.sh"

PROMPT_FILE=""
CHECK_CMD=""
MAX_ITER=5
ACK=0
DRY_RUN=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --i-understand-billing) ACK=1; shift ;;
    --prompt-file)          PROMPT_FILE="$2"; shift 2 ;;
    --check-cmd)            CHECK_CMD="$2"; shift 2 ;;
    --max-iterations)       MAX_ITER="$2"; shift 2 ;;
    --dry-run)              DRY_RUN=1; shift ;;
    --yes)                  ASSUME_YES=1; shift ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

if [[ $ACK -ne 1 ]]; then
  echo "REFUSING TO RUN: billing follows your auth method — an API key in" >&2
  echo "scope (or --bare mode) bills per token instead of your subscription" >&2
  echo "(see the warning at the top of this script)." >&2
  echo "Re-run with --i-understand-billing to proceed." >&2
  exit 2
fi
if [[ -z "$PROMPT_FILE" || ! -f "$PROMPT_FILE" ]]; then
  echo "error: --prompt-file is required and must exist. Write the full task" >&2
  echo "spec (goal, constraints, completion criteria) into it first — the" >&2
  echo "file is re-read on every iteration and IS the loop's memory." >&2
  exit 2
fi
if [[ -z "$CHECK_CMD" ]]; then
  echo "error: --check-cmd is required (e.g. --check-cmd 'npm test')." >&2
  echo "A completion promise from the model alone is unreliable; the loop" >&2
  echo "terminates only when this command exits 0." >&2
  exit 2
fi
command -v claude >/dev/null 2>&1 || { echo "error: claude CLI not found" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 3; }

CMD=(claude -p --output-format json --permission-mode acceptEdits)

if [[ $DRY_RUN -eq 1 ]]; then
  echo "dry run — would execute up to $MAX_ITER iterations of:"
  echo "  cat $PROMPT_FILE | ${CMD[*]}"
  echo "  then: $CHECK_CMD  (loop ends when this exits 0)"
  exit 0
fi

if [[ $ASSUME_YES -ne 1 ]]; then
  echo "About to start a headless loop: up to $MAX_ITER iterations of"
  echo "  cat $PROMPT_FILE | ${CMD[*]}"
  echo "Completion check: $CHECK_CMD"
  read -r -p "Proceed? [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]] || { echo "aborted"; exit 1; }
fi

TOTAL_COST=0
ERR_TMP="$(mktemp)"
trap 'rm -f "$ERR_TMP"' EXIT

# Observability: one run id for the whole loop, exported so shim calls made
# by the headless session correlate to it.
AGENTIC_RUN_ID="hl-$(date +%s)-$$"
export AGENTIC_RUN_ID
obs_event headless_start headless "$(jq -cn \
  --arg pf "$PROMPT_FILE" --arg cc "$CHECK_CMD" --argjson max "$MAX_ITER" \
  '{detail: {prompt_file: $pf, check_cmd: $cc, max_iterations: $max}}')"

# obs_headless_end STATUS EXIT_CODE ITERS_RUN — terminal event for every exit
# path (done / postponed / error / exhausted).
obs_headless_end() {
  obs_event headless_end headless "$(jq -cn \
    --arg s "$1" --argjson c "$2" --argjson n "$3" --argjson total "$TOTAL_COST" \
    '{status: $s, exit_code: $c, est_cost_usd: $total,
      detail: {iterations_run: $n}}')"
}

for ((iter = 1; iter <= MAX_ITER; iter++)); do
  echo "--- iteration $iter/$MAX_ITER $(date '+%H:%M:%S') ---" >&2

  ITER_T0="$(obs_now_ms)"
  RESULT="$(cat "$PROMPT_FILE" | "${CMD[@]}" 2>"$ERR_TMP")" || {
    # Usage-cap backstop: cap errors are NOT retried by the CLI and block
    # until reset — burning further iterations is pure waste. Surface a
    # structured "postponed" outcome instead (exit 7, reset time on stdout).
    COMBINED="${RESULT}"$'\n'"$(cat "$ERR_TMP")"
    if grep -qE "hit your (session|weekly|Opus) limit" <<<"$COMBINED"; then
      RESET_HINT="$(grep -oE 'resets [^"]*' <<<"$COMBINED" | head -1)"
      echo "POSTPONED: subscription usage cap hit on iteration $iter (${RESET_HINT:-reset time unknown})." >&2
      jq -n --arg resets "${RESET_HINT:-unknown}" --argjson iter "$iter" \
        '{status: "postponed", reason: "usage cap", resets: $resets, iterations_run: ($iter - 1)}'
      obs_headless_end postponed 7 "$((iter - 1))"
      exit 7
    fi
    echo "claude -p exited non-zero on iteration $iter" >&2
    sed 's/^/  stderr: /' "$ERR_TMP" >&2
    obs_headless_end error 5 "$((iter - 1))"
    exit 5
  }

  COST="$(echo "$RESULT" | jq -r '.total_cost_usd // 0')"
  TOTAL_COST="$(jq -n --argjson a "$TOTAL_COST" --argjson b "$COST" '$a + $b')"
  echo "iteration $iter cost: \$$COST (cumulative: \$$TOTAL_COST)" >&2

  if bash -c "$CHECK_CMD"; then CHECK_OK=true; else CHECK_OK=false; fi

  obs_event headless_iteration headless "$(echo "$RESULT" | jq -c \
    --argjson iter "$iter" --argjson dur "$(( $(obs_now_ms) - ITER_T0 ))" \
    --argjson total "$TOTAL_COST" --argjson passed "$CHECK_OK" '
    {session_id: (.session_id // null),
     model: (.model // null),
     tier: "headless",
     usage: {input_tokens: (.usage.input_tokens // null),
             output_tokens: (.usage.output_tokens // null),
             cache_read_input_tokens: (.usage.cache_read_input_tokens // null),
             cache_creation_input_tokens: (.usage.cache_creation_input_tokens // null)},
     est_cost_usd: (.total_cost_usd // null),
     duration_ms: $dur,
     status: "ok",
     detail: {iteration: $iter, total_cost_usd: $total,
              check_cmd_passed: $passed}}' 2>/dev/null || echo '{}')"

  if [[ "$CHECK_OK" == "true" ]]; then
    echo "check command passed after iteration $iter — done. Total: \$$TOTAL_COST" >&2
    obs_headless_end ok 0 "$iter"
    exit 0
  fi
  echo "check command still failing; continuing" >&2
done

echo "ESCAPE HATCH: $MAX_ITER iterations exhausted and '$CHECK_CMD' still fails." >&2
echo "Total spend: \$$TOTAL_COST. Review the repo state and git log before re-running." >&2
obs_headless_end exhausted 6 "$MAX_ITER"
exit 6
