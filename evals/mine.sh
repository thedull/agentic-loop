#!/usr/bin/env bash
# mine.sh — the flywheel: mine the observability event log for failures and
# draft eval cases from them (traces → mine → curate evals → experiment).
#
#   ./evals/mine.sh            # scan .agentic/observability/events-*.jsonl
#   ./evals/mine.sh --dry-run  # list what would be drafted
#
# Mined signals:
#   - shim_call with status != ok, or caveats_count > 0
#   - headless_end with status error/exhausted/postponed
#   - tracker_transition into "blocked"
#
# Drafts land in evals/cases/_inbox/ with provenance and a TODO checks stub.
# MINING PROPOSES, HUMANS CURATE: nothing in _inbox runs until it is reviewed,
# given real checks, and moved into a suite directory.

set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBS_DIR=".agentic/observability"
INBOX="$EVALS_DIR/cases/_inbox"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 3; }
ls "$OBS_DIR"/events-*.jsonl >/dev/null 2>&1 || {
  echo "nothing to mine: no event log under $OBS_DIR (enable observability first)" >&2
  exit 0
}

MINED="$(cat "$OBS_DIR"/events-*.jsonl | jq -c '
  select(
    (.event == "shim_call"
      and ((.status != "ok") or ((.detail.caveats_count // 0) > 0)))
    or (.event == "headless_end" and (.status != "ok"))
    or (.event == "tracker_transition" and (.detail.to_status == "blocked"))
  )')"

[[ -n "$MINED" ]] || { echo "nothing to mine: no failure signals in the log"; exit 0; }

N=0
while IFS= read -r ev; do
  ID="mined-$(printf '%s' "$ev" | jq -r '.ts' | tr -dc '0-9' | cut -c1-14)-$N"
  N=$((N+1))
  if [[ $DRY -eq 1 ]]; then
    printf '%s\n' "$ev" | jq -r --arg id "$ID" \
      '"would draft \($id): \(.event) \(.agent_type // "?") status=\(.status // "?") — \(.summary // .detail.objective // "no summary" | tostring | .[0:70])"'
    continue
  fi
  mkdir -p "$INBOX"
  OUT="$INBOX/$ID.json"
  [[ -e "$OUT" ]] && continue
  printf '%s\n' "$ev" | jq --arg id "$ID" '
    {id: $id,
     target: (.agent_type // "unknown"),
     kind: "TODO: bash-unit | shim | headless-agent",
     input: {brief: {objective: (.detail.objective // .summary
                                 // "TODO: reconstruct the objective"),
                     user_intent_verbatim: "", input_paths: [],
                     boundaries_non_goals: [], output_spec: "",
                     effort_budget: ""}},
     checks: [{type: "TODO",
               _hint: "what SHOULD have happened here? encode it as envelope_valid / jq / must_find / judge checks"}],
     provenance: {source: "mined", run_id: .run_id, event_ts: .ts,
                  original_status: .status,
                  original_summary: (.summary // null)}}' > "$OUT"
  echo "drafted: ${OUT#"$EVALS_DIR"/}"
done <<<"$MINED"

[[ $DRY -eq 1 ]] || echo "review the drafts, give them real checks, then move them out of _inbox/ into a suite."
