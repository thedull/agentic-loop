#!/usr/bin/env bash
# observe_push.sh — cursor-based export of the event log to an OpenObserve
# (or any JSON-array-ingesting) store. The export plane of
# docs/observability-architecture.md: capture NEVER depends on this — a
# failed push changes nothing and retries from the cursor next run.
#
# Gated twice (both required — same posture as bench.sh: the script is
# always scaffolded, the behavior is opt-in):
#   1. .agentic/config.json  .observability.stack.enabled == true
#   2. env O2_URL + O2_AUTH  (put them in ./.env — gitignored — and
#      source it before running, or let a launchd/cron wrapper do so)
#
# Env:
#   O2_URL     store base URL, e.g. http://localhost:5080 (or the tailnet name)
#   O2_AUTH    "email:password" — OpenObserve basic auth; NEVER hardcode it
#   O2_ORG     organization (default: default)
#   O2_STREAM  stream name  (default: agentic)
#
# Cursor: .agentic/observability/state/push-cursor.json — {filename: lines
# already pushed}. A file is re-read only past its cursor; the cursor
# advances ONLY after the store acknowledged the batch, so a dead store
# means retry-not-loss. Push before prune: .gz files are skipped (document
# order in the RUNBOOK evening step; at this volume that is one curl/day).
#
#   ./scripts/observe_push.sh            # push everything new
#   ./scripts/observe_push.sh --dry-run  # count what would go, touch nothing
#
# Exit: 0 pushed/nothing-to-do/disabled · 1 store unreachable (cursor kept)
#       2 usage/config error

set -euo pipefail

OBS_DIR="${OBS_DIR:-.agentic/observability}"
CURSOR="$OBS_DIR/state/push-cursor.json"
DRY=0
[[ "${1:-}" == "--dry-run" ]] && DRY=1

# Gate 1: the feature flag.
if [[ "$(jq -r '.observability.stack.enabled // false' .agentic/config.json 2>/dev/null)" != "true" ]]; then
  echo "observe_push: stack disabled — /agentic-loop:config observability stack on" >&2
  exit 0
fi

# Gate 2: credentials. Missing creds is a config gap worth saying out loud
# (the flag says the user WANTS export), but still never an error that could
# break a calling loop.
if [[ -z "${O2_URL:-}" || -z "${O2_AUTH:-}" ]]; then
  echo "observe_push: O2_URL/O2_AUTH not set — add them to ./.env (see templates/observability/README.md)" >&2
  exit 0
fi

O2_ORG="${O2_ORG:-default}"
O2_STREAM="${O2_STREAM:-agentic}"
ENDPOINT="${O2_URL%/}/api/$O2_ORG/$O2_STREAM/_json"
# Test seam: evals swap curl for a recorder. Production never sets this.
CURL_CMD="${O2_CURL:-curl}"

mkdir -p "$OBS_DIR/state"
[[ -f "$CURSOR" ]] || printf '{}' > "$CURSOR"

PUSHED=0 PENDING=0 FAILED=0
shopt -s nullglob
for f in "$OBS_DIR"/events-*.jsonl; do
  base="$(basename "$f")"
  total="$(wc -l < "$f" | tr -d ' ')"
  done_n="$(jq -r --arg k "$base" '.[$k] // 0' "$CURSOR")"
  [[ "$done_n" =~ ^[0-9]+$ ]] || done_n=0
  new=$(( total - done_n ))
  (( new > 0 )) || continue
  PENDING=$((PENDING + new))
  if [[ $DRY -eq 1 ]]; then
    echo "would push: $base lines $((done_n + 1))..$total"
    continue
  fi
  # The store wants one JSON array; the log is JSONL — one slurp away.
  #
  # _timestamp is set from the event's OWN ts (epoch microseconds), never
  # left to the store: OpenObserve falls back to ingest time, which collapses
  # every backfilled event onto the moment of the push. Measured on the first
  # real backfill — 582 events spanning five days all landed at one instant,
  # making every dashboard time filter answer "when did I upload this?"
  # instead of "when did this happen?". That defeats the whole offline-batch
  # design, where uploading late is the expected case. Events whose ts cannot
  # be parsed are sent without the field (store falls back as before) rather
  # than dropped.
  BATCH="$(tail -n +"$((done_n + 1))" "$f" | jq -cs '
    map(if (.ts | type) == "string"
        then . + {_timestamp: ((.ts | sub("\\.[0-9]+"; "")
                               | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) * 1000000)}
        else . end)' 2>/dev/null)"
  [[ -n "$BATCH" ]] || BATCH="$(tail -n +"$((done_n + 1))" "$f" | jq -cs '.')"
  # < /dev/null: the batch travels as an argument, and anything that reads
  # a held-open non-tty stdin hangs forever (the RUNBOOK shim gotcha).
  #
  # HTTP 200 IS NOT ACCEPTANCE. OpenObserve answers a partly- or wholly-
  # rejected batch with 200 and per-stream {successful, failed, error} in the
  # BODY — e.g. "Too old data, only last 5 hours data can be ingested"
  # (ZO_INGEST_ALLOWED_UPTO, default 5h). Trusting the status code advanced
  # the cursor over 582 events the store had discarded: silent loss, and
  # exactly the guarantee this cursor exists to provide. The body decides.
  # `|| RC=$?`, not a bare assignment: under `set -e` a failing command
  # substitution aborts the script outright (the old code was shielded by
  # sitting inside an `if`). Caught by eval 015 the moment it regressed.
  RC=0
  RESP="$("$CURL_CMD" -s -X POST "$ENDPOINT" -u "$O2_AUTH" \
       -H 'Content-Type: application/json' --data-binary "$BATCH" \
       2>/dev/null < /dev/null)" || RC=$?
  REJECTED=0; REASON=""
  if [[ $RC -ne 0 ]]; then
    REJECTED=1; REASON="unreachable (curl exit $RC)"
  elif [[ -n "$RESP" ]]; then
    # An unparseable/among-friends body (test doubles emit nothing) is not
    # evidence of rejection — only an explicit failed>0 is.
    NFAIL="$(jq -r '[.status[]?.failed // 0] | add // 0' <<<"$RESP" 2>/dev/null || echo 0)"
    [[ "$NFAIL" =~ ^[0-9]+$ ]] || NFAIL=0
    if [[ "$NFAIL" -gt 0 ]]; then
      REJECTED=1
      REASON="$(jq -r '[.status[]?.error // empty] | first // "store reported failures"' <<<"$RESP" 2>/dev/null)"
    fi
  fi
  if [[ $REJECTED -eq 0 ]]; then
    TMP="$(mktemp)"
    jq --arg k "$base" --argjson n "$total" '.[$k] = $n' "$CURSOR" > "$TMP" \
      && mv "$TMP" "$CURSOR"
    echo "pushed: $base +$new (cursor $total)"
    PUSHED=$((PUSHED + new))
  else
    echo "observe_push: $base NOT accepted — cursor kept, will retry. Store said: $REASON" >&2
    FAILED=1
  fi
done
shopt -u nullglob

if [[ $DRY -eq 1 ]]; then
  echo "observe_push: $PENDING line(s) pending (dry run)"
else
  echo "observe_push: $PUSHED line(s) pushed"
fi
[[ $FAILED -eq 0 ]] || exit 1
exit 0
