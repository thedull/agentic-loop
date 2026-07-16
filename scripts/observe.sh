#!/usr/bin/env bash
# observe.sh — observability hook entrypoint + manual event emitter.
#
# Registered plugin-level by hooks/hooks.json for SessionStart, SubagentStart,
# SubagentStop and SessionEnd. OPT-IN: a silent no-op unless observability is
# enabled (see scripts/lib/obs.sh). Every path exits 0 — a telemetry hook must
# never block or break the session.
#
# Manual mode (used by skills to record orchestration decisions):
#   observe.sh emit <event> '<overlay-json>'
#   e.g. observe.sh emit feature_toggle \
#          '{"detail":{"feature":"minimize","scope":"task","reason":"mechanical bulk work","decided_by":"agent"}}'
#
# Hook payload facts this script relies on (verified against
# code.claude.com/docs 2026-07-15, with open items flagged in
# docs/observability.md):
#   - SubagentStart/Stop carry agent_id + agent_type; Stop adds
#     last_assistant_message. transcript_path presence on these two events is
#     UNVERIFIED (F1) — token extraction below is best-effort and never fails.
#   - SubagentStart matcher support is contradictory in the docs (F2), so
#     agent filtering happens here in-script, never via matchers.
#   - Transcript JSONL internals are version-dependent (F3): every jq pull
#     uses // fallbacks and tolerates both .message.usage and .usage shapes.

set -uo pipefail # deliberately no -e: nothing here may kill the hook

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/obs.sh" 2>/dev/null || exit 0

# --- manual emitter -----------------------------------------------------------
if [[ "${1:-}" == "emit" ]]; then
  obs_event "${2:-custom}" "skill" "${3:-\{\}}"
  exit 0
fi

# --- hook mode ----------------------------------------------------------------
INPUT="$(cat 2>/dev/null)" || exit 0
[[ -n "$INPUT" ]] || exit 0

# Prefer the payload's cwd for project-root resolution when the plugin env
# var is absent (obs_root checks CLAUDE_PROJECT_DIR first, then this).
OBS_PROJECT_DIR="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
export OBS_PROJECT_DIR

obs_enabled || exit 0

EVT="$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)"
STATE="$(obs_state_dir)"
mkdir -p "$STATE" 2>/dev/null || exit 0

# In-script agent filter (F2): loop-* agents only, unless the config asks for
# every subagent in the tree.
agent_wanted() {
  local t="${1:-}"
  [[ "$t" =~ (^|:)loop- ]] && return 0
  [[ "$(jq -r '.observability.all_agents // false' "$(obs_root)/config.json" \
        2>/dev/null)" == "true" ]]
}

# Tier lookup for the plugin's native subagents. Mirrors the model pinned in
# each agents/*.md frontmatter — keep in sync when retiering agents.
tier_for_agent() {
  case "${1##*:}" in
    loop-worker-cheap)                    echo "haiku" ;;
    loop-planner|loop-consolidator|loop-reviewer) echo "sonnet" ;;
    loop-frontier|loop-reviewer-frontier) echo "fable" ;;
    *)                                    echo "" ;;
  esac
}

case "$EVT" in

  SessionStart)
    # Subagent sessions may fire SessionStart too (they carry agent_type);
    # their lifecycle is captured by SubagentStart/Stop in the parent, so
    # only a root session opens a run.
    AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)"
    if [[ -z "$AGENT_TYPE" && -n "$SID" ]]; then
      [[ -f "$STATE/run" ]] || printf '%s' "$SID" > "$STATE/run" 2>/dev/null
      OVERLAY="$(printf '%s' "$INPUT" | jq -c '
        {session_id: (.session_id // null),
         model: (.model // null),
         detail: {source: (.source // null)}}' 2>/dev/null)" \
        && obs_event run_start hook "$OVERLAY"
    fi
    ;;

  SubagentStart)
    AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)"
    AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)"
    agent_wanted "$AGENT_TYPE" || exit 0
    [[ -n "$AGENT_ID" ]] \
      && printf '%s %s %s' "$(obs_now_ms)" "$SID" "$AGENT_TYPE" \
         > "$STATE/agent-$AGENT_ID.start" 2>/dev/null
    TIER="$(tier_for_agent "$AGENT_TYPE")"
    OVERLAY="$(jq -cn --arg sid "$SID" --arg aid "$AGENT_ID" \
        --arg at "$AGENT_TYPE" --arg tier "$TIER" '
      {session_id: (if $sid == "" then null else $sid end),
       agent_id: (if $aid == "" then null else $aid end),
       agent_type: (if $at == "" then null else $at end),
       tier: (if $tier == "" then null else $tier end)}' 2>/dev/null)" \
      && obs_event agent_start hook "$OVERLAY"
    ;;

  SubagentStop)
    AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null)"
    AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)"
    agent_wanted "$AGENT_TYPE" || exit 0

    DUR=null
    MARKER="$STATE/agent-$AGENT_ID.start"
    if [[ -n "$AGENT_ID" && -f "$MARKER" ]]; then
      START_MS="$(cut -d' ' -f1 "$MARKER" 2>/dev/null)"
      [[ "$START_MS" =~ ^[0-9]+$ ]] && DUR=$(( $(obs_now_ms) - START_MS ))
      rm -f "$MARKER" 2>/dev/null
    fi

    # Best-effort token/model extraction from the subagent transcript (F1/F3).
    USAGE='{"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null}'
    MODEL_JSON=null
    TP="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
    if [[ -n "$TP" && -f "$TP" ]]; then
      EXTRACTED="$(jq -cs '
        [ .[] | (.message.usage // .usage // empty) | objects ] as $u |
        if ($u | length) == 0 then null else
          {input_tokens: ([$u[].input_tokens // 0] | add),
           output_tokens: ([$u[].output_tokens // 0] | add),
           cache_read_input_tokens: ([$u[].cache_read_input_tokens // 0] | add),
           cache_creation_input_tokens: ([$u[].cache_creation_input_tokens // 0] | add)}
        end' "$TP" 2>/dev/null)"
      [[ -n "$EXTRACTED" && "$EXTRACTED" != "null" ]] && USAGE="$EXTRACTED"
      M="$(jq -rs '[ .[] | (.message.model // .model // empty) | strings ] | last // empty' \
           "$TP" 2>/dev/null)"
      [[ -n "$M" ]] && MODEL_JSON="$(jq -cn --arg m "$M" '$m')"
    fi

    TIER="$(tier_for_agent "$AGENT_TYPE")"
    OVERLAY="$(printf '%s' "$INPUT" | jq -c \
        --arg tier "$TIER" --argjson dur "$DUR" \
        --argjson usage "$USAGE" --argjson model "$MODEL_JSON" '
      {session_id: (.session_id // null),
       agent_id: (.agent_id // null),
       agent_type: (.agent_type // null),
       tier: (if $tier == "" then null else $tier end),
       model: $model,
       usage: $usage,
       duration_ms: $dur,
       summary: ((.last_assistant_message // null) | if . == null then null else .[0:1000] end),
       detail: {transcript_path: (.transcript_path // null)}}' 2>/dev/null)" \
      && obs_event agent_stop hook "$OVERLAY"
    ;;

  SessionEnd)
    AGENT_TYPE="$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)"
    if [[ -z "$AGENT_TYPE" && -n "$SID" ]]; then
      # Emit BEFORE removing the run marker so the event carries the run_id.
      OVERLAY="$(printf '%s' "$INPUT" | jq -c '
        {session_id: (.session_id // null),
         detail: {reason: (.reason // null)}}' 2>/dev/null)" \
        && obs_event run_end hook "$OVERLAY"
      if [[ -f "$STATE/run" && "$(cat "$STATE/run" 2>/dev/null)" == "$SID" ]]; then
        rm -f "$STATE/run" 2>/dev/null
      fi
    fi
    ;;

esac

exit 0
