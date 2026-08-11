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
# Stage-context mode (used by the factory skills at claim/exit — makes every
# event in the run carry phase/spec_id; see obs_set_context in lib/obs.sh):
#   observe.sh context set --phase build --spec-id factory/specs/007-x.md
#   observe.sh context clear
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

# --- diff size (spec 013) ------------------------------------------------------
# No hook fires at the moment a diff exists, so the review stage emits this
# explicitly. Nulls are honest: an unresolvable ref or an empty diff yields
# null, never 0 — "a diff of no lines" and "we could not tell" are different
# facts, and the whole comprehension metric family rests on the distinction.
if [[ "${1:-}" == "diff-size" ]]; then
  shift
  DS_BASE=""; DS_HEAD="HEAD"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) DS_BASE="${2:-}"; shift 2 ;;
      --head) DS_HEAD="${2:-}"; shift 2 ;;
      *) shift ;;
    esac
  done
  DS_ADD=null; DS_DEL=null
  if [[ -n "$DS_BASE" ]] \
     && git rev-parse --verify --quiet "$DS_BASE" >/dev/null 2>&1 \
     && git rev-parse --verify --quiet "$DS_HEAD" >/dev/null 2>&1; then
    # numstat prints "-" for binary files. Coercing that to 0 fabricates
    # "no diff" for a real one — the exact null-vs-zero collapse acceptance 3
    # forbids. Count only rows carrying real numbers; if NOTHING was countable,
    # the answer is null, not zero.
    DS_STAT="$(git diff --numstat "$DS_BASE" "$DS_HEAD" 2>/dev/null \
               | awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {a+=$1; d+=$2; n++}
                      END {if (n>0) printf "%d %d", a, d}')"
    if [[ -n "$DS_STAT" ]]; then
      DS_ADD="${DS_STAT%% *}"; DS_DEL="${DS_STAT##* }"
    fi
  fi
  obs_event diff_size skill "$(jq -cn --argjson a "$DS_ADD" --argjson d "$DS_DEL" \
    '{detail: {lines_added: $a, lines_removed: $d}}')"
  exit 0
fi

# --- stage context -------------------------------------------------------------
if [[ "${1:-}" == "context" ]]; then
  shift
  case "${1:-}" in
    set)
      shift
      CTX_PHASE="" CTX_SPEC_ID=""
      while [[ $# -gt 0 ]]; do
        case "$1" in
          --phase)   CTX_PHASE="${2:-}";   shift 2 ;;
          --spec-id) CTX_SPEC_ID="${2:-}"; shift 2 ;;
          *) shift ;;
        esac
      done
      obs_set_context "$CTX_PHASE" "$CTX_SPEC_ID"
      ;;
    clear)
      obs_clear_context
      ;;
  esac
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
    #
    # DEDUPE BY MESSAGE ID, never sum per line: one API response spans
    # several transcript lines (one per content block / tool_use), each
    # repeating the SAME usage object. A naive per-line sum multiplies every
    # call by its block count — measured 2.6x on a real transcript, and the
    # field failure that forced this fix was a single agent_stop claiming
    # 2.28M output tokens. One usage per message id (max_by output_tokens,
    # in case a stream writes progressive usage); lines with usage but no
    # message id (older transcript shapes) cannot be deduped and are kept
    # as-is, preserving the previous behavior exactly for those shapes.
    #
    # ATTRIBUTION GUARD (field evidence, 2026-07-31): SubagentStop's
    # transcript_path is frequently the PARENT SESSION's transcript, not the
    # subagent's — 136 distinct agent_stop events in one project all pointed
    # at a single 8473-line file whose sessionId equalled the event's own
    # session_id. Extracting from that reports the whole session's usage for
    # each subagent, which is how a single agent_stop came to claim 2.28M
    # output tokens. There is no per-agent usage in that file to recover, so
    # we do not invent one: when the transcript's session matches this event's
    # session, usage and model stay NULL and detail.usage_source says why.
    # This is the "nulls are honest" rule (lib/obs.sh) applied to its own
    # capture path. When the CLI does hand over a genuine child transcript
    # (different sessionId), extraction proceeds as before — so this
    # future-proofs rather than disables.
    USAGE='{"input_tokens":null,"output_tokens":null,"cache_read_input_tokens":null,"cache_creation_input_tokens":null}'
    MODEL_JSON=null
    USAGE_SRC=null
    TP="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)"
    TP_SID=""
    if [[ -n "$TP" && -f "$TP" ]]; then
      TP_SID="$(jq -rs '[ .[] | .sessionId // empty ] | last // empty' "$TP" 2>/dev/null)"
    fi
    if [[ -n "$TP" && -f "$TP" && -n "$TP_SID" && "$TP_SID" == "$SID" ]]; then
      USAGE_SRC='"parent-transcript-not-attributable"'
      TP=""   # skip extraction entirely; nothing here belongs to this subagent
    fi
    if [[ -n "$TP" && -f "$TP" ]]; then
      USAGE_SRC='"subagent-transcript"'
      EXTRACTED="$(jq -cs '
        [ .[] | {mid: (.message.id // null),
                 u: ((.message.usage // .usage // empty) | objects)} ] as $e |
        if ($e | length) == 0 then null else
          ( ($e | map(select(.mid != null)) | group_by(.mid)
              | map(max_by(.u.output_tokens // 0) | .u))
            + ($e | map(select(.mid == null) | .u)) ) as $u |
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
    # Findings count comes from the reviewer's OWN envelope in the full
    # message. Deliberately NOT from `summary`, which is truncated to 1000
    # chars below — a verbose but complete review would silently read as null.
    # null means "no parseable envelope"; 0 means "a clean review". Opposite
    # signals, never collapsed.
    # Two separate defects lived here, both found on 2026-08-11 by reviewing a
    # real reviewer envelope rather than a hand-written one:
    #
    #   1. The old `sed -e 's/^[^{]*//' -e 's/[^}]*$//'` runs PER LINE. On a
    #      pretty-printed envelope it deletes content on every line and the
    #      count silently became null. finalize_envelope emits pretty JSON by
    #      default, so this was the common case, not the edge case.
    #   2. It read only a top-level `.findings`. A Task-tool subagent's message
    #      never passes through finalize_envelope, so nothing normalises it, and
    #      a reviewer that answers with result.findings — which the live model
    #      did — counted as null.
    #
    # null still means "no parseable envelope" and 0 still means "a clean
    # review". Opposite signals, never collapsed.
    MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // ""' 2>/dev/null)"
    CAND=""
    if [[ "$MSG" == *"{"* && "$MSG" == *"}"* ]]; then
      CAND="{${MSG#*\{}"          # drop any prose before the first brace
      CAND="${CAND%\}*}}"          # drop any prose after the last brace
    fi
    FINDINGS="$(printf '%s' "$CAND" \
      | jq -e 'if (.findings|type) == "array" then (.findings|length)
               elif ((.result|type) == "object") and ((.result.findings|type) == "array")
                 then (.result.findings|length)
               else empty end' 2>/dev/null \
        | tail -1)"
    # Guard the value itself. Two JSON objects in one message make jq stream two
    # results, and a multi-line value breaks --argjson below — which takes the
    # ENTIRE agent_stop event down with it. A telemetry hook must never lose the
    # event it was called to record.
    [[ "$FINDINGS" =~ ^[0-9]+$ ]] || FINDINGS=null

    OVERLAY="$(printf '%s' "$INPUT" | jq -c \
        --arg tier "$TIER" --argjson dur "$DUR" \
        --argjson findings "$FINDINGS" \
        --argjson usage "$USAGE" --argjson model "$MODEL_JSON" \
        --argjson usrc "$USAGE_SRC" '
      {session_id: (.session_id // null),
       agent_id: (.agent_id // null),
       agent_type: (.agent_type // null),
       tier: (if $tier == "" then null else $tier end),
       model: $model,
       usage: $usage,
       duration_ms: $dur,
       summary: ((.last_assistant_message // null) | if . == null then null else .[0:1000] end),
       detail: {transcript_path: (.transcript_path // null),
                usage_source: $usrc,
                findings_count: $findings}}' 2>/dev/null)" \
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
