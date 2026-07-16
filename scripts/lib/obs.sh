#!/usr/bin/env bash
# obs.sh — opt-in observability helpers: unified JSONL event log.
#
# Sourced by scripts/observe.sh (hook entrypoint), scripts/lib/common.sh
# (shim tap), scripts/run_headless.sh, scripts/lib/tracker.sh and
# scripts/lib/usage_gate.sh.
#
# Contract (telemetry must never break the loop):
#   - OPT-IN. Silent no-op unless .agentic/config.json has
#     .observability.enabled == true, or AGENTIC_OBSERVE=1 is set.
#     AGENTIC_OBSERVE=0 is a hard off that wins over the config file.
#   - NEVER fatal, NEVER prints to stdout (stdout belongs to envelopes and
#     JSON results). Every failure path is swallowed.
#   - One unified append-only log: .agentic/observability/events-YYYYMMDD.jsonl.
#     Single-line O_APPEND writes are atomic at these line sizes; that is the
#     whole concurrency story (same pragmatism as tracker.sh's mkdir locks).
#   - Event schema v1 (docs/observability.md). Nulls are honest — never
#     fabricate tokens or costs a source did not report. est_cost_usd stays
#     null for subscription tiers: they are shared capacity, not dollars.

# Resolution order for the project root: plugin hooks get CLAUDE_PROJECT_DIR;
# observe.sh sets OBS_PROJECT_DIR from the hook payload's cwd; shims and
# run_headless.sh run from the project directory already.
obs_root() {
  printf '%s' "${CLAUDE_PROJECT_DIR:-${OBS_PROJECT_DIR:-$PWD}}/.agentic"
}

obs_enabled() {
  [[ "${AGENTIC_OBSERVE:-}" == "0" ]] && return 1
  [[ "${AGENTIC_OBSERVE:-}" == "1" ]] && return 0
  local cfg
  cfg="$(obs_root)/config.json"
  [[ -f "$cfg" ]] || return 1
  [[ "$(jq -r '.observability.enabled // false' "$cfg" 2>/dev/null)" == "true" ]]
}

# Millisecond clock. bash >= 5 has EPOCHREALTIME; stock macOS bash 3.2 does
# not, so fall back to perl (ships with macOS), then to second precision.
obs_now_ms() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local s="${EPOCHREALTIME%.*}" frac="${EPOCHREALTIME#*.}"
    echo $(( s * 1000 + 10#${frac:0:3} ))
  elif command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d", time()*1000'
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}

obs_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

obs_state_dir() { printf '%s' "$(obs_root)/observability/state"; }

# Current run id: env override first (run_headless.sh exports AGENTIC_RUN_ID),
# then the marker written by the SessionStart hook, else "adhoc".
obs_run_id() {
  if [[ -n "${AGENTIC_RUN_ID:-}" ]]; then
    printf '%s' "$AGENTIC_RUN_ID"
  elif [[ -f "$(obs_state_dir)/run" ]]; then
    cat "$(obs_state_dir)/run" 2>/dev/null || printf 'adhoc'
  else
    printf 'adhoc'
  fi
}

# obs_event EVENT SOURCE [OVERLAY_JSON]
# Appends one schema-v1 line, deep-merging OVERLAY_JSON over the base
# skeleton. Invalid overlays lose the event rather than break the caller.
obs_event() {
  obs_enabled || return 0
  local event="$1" source="$2" overlay="${3:-\{\}}" dir
  dir="$(obs_root)/observability"
  mkdir -p "$dir" 2>/dev/null || return 0
  jq -cn --arg ts "$(obs_ts)" --arg event "$event" --arg source "$source" \
         --arg run_id "$(obs_run_id)" --argjson overlay "$overlay" '
    {v: 1, ts: $ts, event: $event, source: $source, run_id: $run_id,
     session_id: null, agent_id: null, agent_type: null, tier: null,
     model: null,
     usage: {input_tokens: null, output_tokens: null,
             cache_read_input_tokens: null, cache_creation_input_tokens: null},
     est_cost_usd: null, duration_ms: null, status: null, exit_code: null,
     summary: null, detail: {}} * $overlay
  ' >> "$dir/events-$(date +%Y%m%d).jsonl" 2>/dev/null || true
  return 0
}

# Map an envelope worker name to its tier label.
obs_tier_from_worker() {
  case "${1:-}" in
    ollama/*)     echo "ollama" ;;
    openrouter/*) echo "openrouter" ;;
    fable*)       echo "fable" ;;
    sol*)         echo "sol" ;;
    *)            echo "" ;;
  esac
}

# obs_shim_tap — pass-through tee for worker envelopes.
# Reads the final envelope on stdin, echoes it UNCHANGED (stdout contract
# untouched), and appends one shim_call event when observability is on.
# Reads globals when set: MODEL (exact model id), OBJECTIVE (brief field,
# becomes the future eval-case seed), OBS_T0 (ms timer set when common.sh
# was sourced).
obs_shim_tap() {
  local env_json
  env_json="$(cat)"
  printf '%s\n' "$env_json"
  obs_enabled || return 0
  local dur=null
  [[ -n "${OBS_T0:-}" ]] && dur=$(( $(obs_now_ms) - OBS_T0 ))
  local overlay
  overlay="$(printf '%s' "$env_json" | jq -c \
      --arg model "${MODEL:-}" --arg objective "${OBJECTIVE:-}" \
      --argjson dur "$dur" '
    {agent_type: (.worker // null),
     model: (if $model == "" then null else $model end),
     usage: {input_tokens: (.usage.input_tokens // null),
             output_tokens: (.usage.output_tokens // null),
             cache_read_input_tokens: null, cache_creation_input_tokens: null},
     est_cost_usd: (.usage.est_cost_usd // null),
     duration_ms: $dur,
     status: (.status // null),
     summary: (.summary // null),
     detail: {objective: (if $objective == "" then null
                          else ($objective | .[0:300]) end),
              artifacts: (.artifacts // []),
              caveats_count: ((.caveats // []) | length)}}
  ' 2>/dev/null)" || return 0
  local tier
  tier="$(obs_tier_from_worker "$(printf '%s' "$env_json" \
          | jq -r '.worker // empty' 2>/dev/null)")"
  if [[ -n "$tier" ]]; then
    overlay="$(printf '%s' "$overlay" \
      | jq -c --arg tier "$tier" '.tier = $tier' 2>/dev/null || printf '%s' "$overlay")"
  fi
  obs_event shim_call shim "$overlay"
  return 0
}
