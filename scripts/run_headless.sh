#!/usr/bin/env bash
# run_headless.sh — GATED wrapper for unattended `claude -p` loop runs.
#
# ############################  BILLING WARNING  ##############################
# Headless / autonomous usage (claude -p, Agent SDK, CI) is metered DIFFERENTLY
# from your interactive Max subscription session. Reports through 2026 describe
# a separate monthly credit followed by API-rate billing, with large cost jumps
# for heavy automated workloads. The exact policy is volatile and NOT fully
# confirmed in official docs — verify your plan's current terms before relying
# on this. This script refuses to run without --i-understand-billing.
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
  echo "REFUSING TO RUN: headless usage is billed differently from your" >&2
  echo "interactive Max session (see the warning at the top of this script)." >&2
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
for ((iter = 1; iter <= MAX_ITER; iter++)); do
  echo "--- iteration $iter/$MAX_ITER $(date '+%H:%M:%S') ---" >&2

  RESULT="$(cat "$PROMPT_FILE" | "${CMD[@]}")" || {
    echo "claude -p exited non-zero on iteration $iter" >&2
    exit 5
  }

  COST="$(echo "$RESULT" | jq -r '.total_cost_usd // 0')"
  TOTAL_COST="$(jq -n --argjson a "$TOTAL_COST" --argjson b "$COST" '$a + $b')"
  echo "iteration $iter cost: \$$COST (cumulative: \$$TOTAL_COST)" >&2

  if bash -c "$CHECK_CMD"; then
    echo "check command passed after iteration $iter — done. Total: \$$TOTAL_COST" >&2
    exit 0
  fi
  echo "check command still failing; continuing" >&2
done

echo "ESCAPE HATCH: $MAX_ITER iterations exhausted and '$CHECK_CMD' still fails." >&2
echo "Total spend: \$$TOTAL_COST. Review the repo state and git log before re-running." >&2
exit 6
