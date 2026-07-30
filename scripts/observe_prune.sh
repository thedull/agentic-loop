#!/usr/bin/env bash
# observe_prune.sh — retention for the observability log. Manual by design:
# doctor.sh nudges when things grow, but nothing prunes during an unattended
# run (no silent mutation of the source of truth while a stage may read it).
#
#   ./scripts/observe_prune.sh                  # gzip event files >30 days old,
#                                               # keep the newest 20 HTML reports
#   ./scripts/observe_prune.sh --days 7         # tighter event window
#   ./scripts/observe_prune.sh --keep-reports 5
#   ./scripts/observe_prune.sh --dry-run        # say it, don't do it
#
# Never lossy: events are COMPRESSED, not deleted — observe_metrics.sh,
# observe_render.sh and evals/mine.sh all read .jsonl.gz transparently.
# Only reports/ (regenerable artifacts) are actually removed.
# Today's live file is never touched regardless of --days.

set -euo pipefail

OBS_DIR="${OBS_DIR:-.agentic/observability}"
DAYS=30 KEEP_REPORTS=20 DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days)         DAYS="${2:-30}"; shift 2 ;;
    --keep-reports) KEEP_REPORTS="${2:-20}"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    *) echo "usage: observe_prune.sh [--days N] [--keep-reports N] [--dry-run]" >&2; exit 2 ;;
  esac
done

[[ "$DAYS" =~ ^[0-9]+$ && "$KEEP_REPORTS" =~ ^[0-9]+$ ]] \
  || { echo "observe_prune: --days/--keep-reports take integers" >&2; exit 2; }

if [[ ! -d "$OBS_DIR" ]]; then
  echo "observe_prune: nothing to prune ($OBS_DIR does not exist)"
  exit 0
fi

TODAY="events-$(date +%Y%m%d).jsonl"
GZIPPED=0 REMOVED=0 HELD=0

# Offline-batching guard: when the export stack is enabled, never gzip lines
# the store has not acknowledged — observe_push.sh reads live .jsonl only, so
# compressing an unpushed file would silently drop its events from the store
# (a long-offline laptop is exactly when both "old file" and "unpushed" are
# true at once). Stack off = nothing to hold for; compress freely.
STACK_ON="$(jq -r '.observability.stack.enabled // false' .agentic/config.json 2>/dev/null || echo false)"
PUSH_CURSOR="$OBS_DIR/state/push-cursor.json"

# --- events: gzip anything older than the window ------------------------------
# File age comes from the DATE IN THE NAME, not mtime — a file's mtime is its
# last append, but its name says which day it holds, and that is the honest
# retention key.
CUTOFF="$(date -v -"${DAYS}"d +%Y%m%d 2>/dev/null || date -d "-${DAYS} days" +%Y%m%d)"
shopt -s nullglob
for f in "$OBS_DIR"/events-*.jsonl; do
  base="$(basename "$f")"
  [[ "$base" == "$TODAY" ]] && continue
  stamp="${base#events-}"; stamp="${stamp%.jsonl}"
  [[ "$stamp" =~ ^[0-9]{8}$ ]] || continue
  if [[ "$stamp" -lt "$CUTOFF" ]]; then
    if [[ "$STACK_ON" == "true" ]]; then
      total="$(wc -l < "$f" | tr -d ' ')"
      pushed="$(jq -r --arg k "$base" '.[$k] // 0' "$PUSH_CURSOR" 2>/dev/null || echo 0)"
      [[ "$pushed" =~ ^[0-9]+$ ]] || pushed=0
      if (( pushed < total )); then
        echo "held: $f — $((total - pushed)) line(s) not yet acknowledged by the export stack; run observe_push.sh first" >&2
        HELD=$((HELD+1))
        continue
      fi
    fi
    if [[ $DRY -eq 1 ]]; then
      echo "would gzip: $f"
    else
      gzip -9 "$f" && echo "gzipped: $f"
    fi
    GZIPPED=$((GZIPPED+1))
  fi
done

# --- reports: cap by count, newest kept ---------------------------------------
if [[ -d "$OBS_DIR/reports" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ $DRY -eq 1 ]]; then
      echo "would remove: $f"
    else
      rm -f "$f" && echo "removed: $f"
    fi
    REMOVED=$((REMOVED+1))
  done < <(ls -t "$OBS_DIR"/reports/*.html 2>/dev/null | tail -n +"$((KEEP_REPORTS + 1))")
fi
shopt -u nullglob

echo "observe_prune: $GZIPPED event file(s) $([[ $DRY -eq 1 ]] && echo 'would be ')gzipped, $REMOVED report(s) $([[ $DRY -eq 1 ]] && echo 'would be ')removed$([[ $HELD -gt 0 ]] && echo ", $HELD held for unpushed lines") (window ${DAYS}d, reports cap $KEEP_REPORTS)"
