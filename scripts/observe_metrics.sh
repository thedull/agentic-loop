#!/usr/bin/env bash
# observe_metrics.sh — local metrics engine over the observability event log.
# Zero infrastructure: bash + jq over .agentic/observability/events-*.jsonl
# (gzip-rotated files included). The derive plane of
# docs/observability-architecture.md — fully useful without any dashboard.
#
#   ./scripts/observe_metrics.sh cost                    # metered $ vs subscription tokens, by tier
#   ./scripts/observe_metrics.sh phase                   # spend + reliability per stage
#   ./scripts/observe_metrics.sh spec                    # per-spec: tokens, errors, reopens, cycle time
#   ./scripts/observe_metrics.sh spec factory/specs/001-x.md   # one spec
#   ./scripts/observe_metrics.sh estimate                # tokens/$ percentiles per effort_budget
#   ./scripts/observe_metrics.sh estimate --effort-budget medium
#   ./scripts/observe_metrics.sh mix                     # deterministic vs stochastic activity
#
# Common flags: --since YYYY-MM-DD  --until YYYY-MM-DD  --format json|tsv
#
# Reads only; exit 2 on usage errors, 1 when there is no event log yet.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# obs_no_events_hint() lives in lib/obs.sh, which ships in the same `core`
# manifest set as this script — but a project can hold a stale or partially
# updated scaffold, and a hard `source` would abort the whole reader under
# `set -e` just to phrase one message. Degrade instead.
if [[ -r "$SCRIPT_DIR/lib/obs.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/obs.sh"
fi
declare -F obs_no_events_hint >/dev/null 2>&1 || obs_no_events_hint() {
  printf 'no event log under %s — enable observability first (/agentic-loop:config observability on)' "${1:-}"
}
OBS_DIR="${OBS_DIR:-.agentic/observability}"
SPECS_DIR="${FACTORY_SPECS_DIR:-factory/specs}"

MODE="${1:-}"
case "$MODE" in
  cost|phase|spec|estimate|mix) shift ;;
  *) echo "usage: observe_metrics.sh cost|phase|spec|estimate|mix [--since D] [--until D] [--format json|tsv] [--effort-budget B]" >&2
     exit 2 ;;
esac

SINCE="" UNTIL="" FORMAT="json" BUDGET="" ONE_SPEC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)         SINCE="${2:-}"; shift 2 ;;
    --until)         UNTIL="${2:-}"; shift 2 ;;
    --format)        FORMAT="${2:-json}"; shift 2 ;;
    --effort-budget) BUDGET="${2:-}"; shift 2 ;;
    --*) echo "observe_metrics: unknown flag $1" >&2; exit 2 ;;
    *) ONE_SPEC="$1"; shift ;;   # spec mode: a single spec path filter
  esac
done

shopt -s nullglob
EVENT_FILES=("$OBS_DIR"/events-*.jsonl)
GZ_FILES=("$OBS_DIR"/events-*.jsonl.gz)
shopt -u nullglob
if [[ ${#EVENT_FILES[@]} -eq 0 && ${#GZ_FILES[@]} -eq 0 ]]; then
  echo "observe_metrics: $(obs_no_events_hint "$OBS_DIR")" >&2
  exit 1
fi

# All events, live + gzip-rotated, in one stream (order irrelevant: every
# computation sorts or groups by its own keys).
_events_cat() {
  if [[ ${#EVENT_FILES[@]} -gt 0 ]]; then cat "${EVENT_FILES[@]}"; fi
  if [[ ${#GZ_FILES[@]} -gt 0 ]]; then gzip -dc "${GZ_FILES[@]}" 2>/dev/null || true; fi
}

# Spec-file facts jq cannot read on its own: id/title/profile from
# frontmatter, effort_budget from the Brief bullet, size in bytes. Keyed by
# path relative to the project root — the same string tracker events carry.
_spec_meta() {
  local f id title profile budget bytes first=1
  printf '{'
  if [[ -d "$SPECS_DIR" ]]; then
    for f in "$SPECS_DIR"/*.md; do
      [[ -e "$f" ]] || continue
      id="$(awk -F': ' '/^id: /{print $2; exit}' "$f" 2>/dev/null || true)"
      title="$(awk -F': ' '/^title: /{print $2; exit}' "$f" 2>/dev/null || true)"
      profile="$(awk -F': ' '/^profile: /{print $2; exit}' "$f" 2>/dev/null || true)"
      budget="$(grep -m1 -oE 'effort_budget:[[:space:]]*[a-z]+' "$f" 2>/dev/null \
                | awk -F': *' '{print $2}' || true)"
      bytes="$(wc -c < "$f" | tr -d ' ')"
      [[ $first -eq 1 ]] || printf ','
      first=0
      jq -cn --arg k "$f" --arg id "$id" --arg t "$title" --arg p "$profile" \
             --arg b "$budget" --argjson bytes "$bytes" \
        '{($k): {id: (if $id == "" then null else $id end),
                 title: (if $t == "" then null else $t end),
                 profile: (if $p == "" then null else $p end),
                 effort_budget: (if $b == "" then null else $b end),
                 bytes: $bytes}}' | sed 's/^{//; s/}$//'
    done
  fi
  printf '}'
}

SPECMETA='{}'
if [[ "$MODE" == "spec" || "$MODE" == "estimate" ]]; then
  SPECMETA="$(_spec_meta)"
fi

# Two passes: a line-wise date filter, then the slurped rollup module.
RESULT="$(_events_cat \
  | jq -c --arg since "$SINCE" --arg until "$UNTIL" '
      select(.v == 1)
      | select($since == "" or .ts >= $since)
      | select($until == "" or .ts[0:10] <= $until)' \
  | jq -s -f "$SCRIPT_DIR/lib/obs_metrics.jq" \
      --arg mode "$MODE" --arg budget "$BUDGET" --argjson specmeta "$SPECMETA")"

# Single-spec filter (spec mode positional arg).
if [[ "$MODE" == "spec" && -n "$ONE_SPEC" ]]; then
  RESULT="$(jq --arg s "$ONE_SPEC" 'map(select(.spec == $s))' <<<"$RESULT")"
fi

if [[ "$FORMAT" == "tsv" ]]; then
  case "$MODE" in
    spec)
      { printf 'spec\teffort_budget\tin_tok\tout_tok\tmetered_usd\tllm_errors\treopens\tcycle_machine_ms\tcycle_merge_ms\n'
        jq -r '.[] | [.spec, (.effort_budget // "-"), .input_tokens, .output_tokens,
                      .metered_usd, .llm_errors, .reopens,
                      (.cycle_machine_ms // "-"), (.cycle_merge_ms // "-")] | @tsv' <<<"$RESULT"; } ;;
    phase)
      { printf 'phase\tevents\tin_tok\tout_tok\tmetered_usd\tllm_errors\tp50_ms\tp90_ms\n'
        jq -r 'to_entries[] | [.key, .value.events, .value.input_tokens,
                      .value.output_tokens, .value.metered_usd, .value.llm_errors,
                      (.value.p50_duration_ms // "-"), (.value.p90_duration_ms // "-")] | @tsv' <<<"$RESULT"; } ;;
    estimate)
      { printf 'effort_budget\tn\tsufficient\ttok_p25\ttok_p50\ttok_p75\tusd_p50\n'
        jq -r '.[] | [.effort_budget, .n, .sufficient, (.tokens.p25 // "-"),
                      (.tokens.p50 // "-"), (.tokens.p75 // "-"),
                      (.metered_usd.p50 // "-")] | @tsv' <<<"$RESULT"; } ;;
    *) printf '%s\n' "$RESULT" ;;   # cost/mix stay json — nested by design
  esac
else
  printf '%s\n' "$RESULT"
fi
