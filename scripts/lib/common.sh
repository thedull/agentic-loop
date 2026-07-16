#!/usr/bin/env bash
# Shared conventions for agentic-loop worker shim scripts.
#
# Contract (all call_*.sh scripts):
#   INPUT  — a 6-field delegation brief, either as JSON on stdin or via flags:
#            --objective "<imperative sentence>"          (required)
#            --user-intent "<verbatim user request>"      (recommended)
#            --input-path <file>                          (repeatable; contents are inlined)
#            --boundary "<non-goal or constraint>"        (repeatable)
#            --output-spec "<what result must contain>"   (recommended)
#            --effort-budget "<scope guidance>"           (optional)
#            --artifact <path>   write the raw model response to this file and
#                                reference it in the envelope's artifacts[]
#   OUTPUT — a single JSON worker envelope on stdout (validated against
#            lib/validate_envelope.jq). Non-zero exit + status:"error" envelope
#            on any failure. Nothing else is ever printed to stdout.
#
# Keys are read from ./.env in the CURRENT PROJECT DIRECTORY, never from the
# exported shell environment. Never name the Anthropic worker key
# ANTHROPIC_API_KEY — that would flip the interactive Claude Code session from
# subscription billing to API billing.

set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$LIB_DIR/validate_envelope.jq"

# Opt-in observability (no-op unless enabled — see lib/obs.sh). The timer set
# here gives every shim call its duration_ms.
# shellcheck disable=SC1091
source "$LIB_DIR/obs.sh"
OBS_T0="$(obs_now_ms)"

die_tool_missing() {
  local tool="$1"
  echo "error: required tool '$tool' not found on PATH" >&2
  exit 3
}

command -v jq >/dev/null 2>&1 || die_tool_missing jq
command -v curl >/dev/null 2>&1 || die_tool_missing curl

# --- .env loading ------------------------------------------------------------
# Reads KEY=value lines from ./.env (project cwd). Does NOT export to children
# beyond this process. Ignores comments and blank lines.
load_env() {
  if [[ -f ./.env ]]; then
    set -a
    # shellcheck disable=SC1091
    source ./.env
    set +a
  fi
}

# require_key VAR_NAME worker_label — fail with a structured error envelope if unset.
require_key() {
  local var="$1" worker="$2"
  if [[ -z "${!var:-}" ]]; then
    emit_error "$worker" "missing credential: $var is not set. Add it to ./.env (see .env.example). Never name an Anthropic key ANTHROPIC_API_KEY."
    exit 2
  fi
}

# --- envelope helpers --------------------------------------------------------

# emit_error worker message — print a valid error envelope and return.
# Tapped for observability: failed calls are exactly what the eval-mining
# flywheel wants to see.
emit_error() {
  local worker="$1" msg="$2"
  jq -n --arg worker "$worker" --arg msg "$msg" '{
    worker: $worker, status: "error", summary: $msg, result: null,
    artifacts: [], key_decisions: [], caveats: [], assumptions: [],
    confidence_ordinal: "low",
    usage: {input_tokens: 0, output_tokens: 0, est_cost_usd: 0}
  }' | obs_shim_tap
}

# validate_envelope — read envelope on stdin; echo it if valid, else exit 4.
validate_envelope() {
  local env_json
  env_json="$(cat)"
  if echo "$env_json" | jq -e -f "$VALIDATOR" >/dev/null 2>&2; then
    echo "$env_json" | obs_shim_tap
  else
    echo "$env_json" | jq -e -f "$VALIDATOR" >/dev/null 2>&1 || true
    emit_error "${WORKER_NAME:-unknown}" "worker produced an envelope that failed schema validation"
    exit 4
  fi
}

# --- brief parsing -----------------------------------------------------------
# Populates: OBJECTIVE, USER_INTENT, OUTPUT_SPEC, EFFORT_BUDGET, ARTIFACT_PATH,
# INPUT_PATHS (array), BOUNDARIES (array), EXTRA_ARGS (array, script-specific
# flags left over for the caller to handle).
parse_brief() {
  OBJECTIVE="" USER_INTENT="" OUTPUT_SPEC="" EFFORT_BUDGET="" ARTIFACT_PATH=""
  INPUT_PATHS=() BOUNDARIES=() EXTRA_ARGS=()

  # If stdin is a pipe/file, treat it as a JSON brief.
  if [[ ! -t 0 ]]; then
    local brief
    brief="$(cat)"
    if [[ -n "$brief" ]]; then
      OBJECTIVE="$(echo "$brief" | jq -r '.objective // empty')"
      USER_INTENT="$(echo "$brief" | jq -r '.user_intent_verbatim // empty')"
      OUTPUT_SPEC="$(echo "$brief" | jq -r '.output_spec // empty')"
      EFFORT_BUDGET="$(echo "$brief" | jq -r '.effort_budget // empty')"
      while IFS= read -r p; do [[ -n "$p" ]] && INPUT_PATHS+=("$p"); done \
        < <(echo "$brief" | jq -r '(.input_paths // [])[]')
      while IFS= read -r b; do [[ -n "$b" ]] && BOUNDARIES+=("$b"); done \
        < <(echo "$brief" | jq -r '(.boundaries_non_goals // [])[]')
    fi
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --objective)     OBJECTIVE="$2"; shift 2 ;;
      --user-intent)   USER_INTENT="$2"; shift 2 ;;
      --input-path)    INPUT_PATHS+=("$2"); shift 2 ;;
      --boundary)      BOUNDARIES+=("$2"); shift 2 ;;
      --output-spec)   OUTPUT_SPEC="$2"; shift 2 ;;
      --effort-budget) EFFORT_BUDGET="$2"; shift 2 ;;
      --artifact)      ARTIFACT_PATH="$2"; shift 2 ;;
      *)               EXTRA_ARGS+=("$1"); shift ;;
    esac
  done

  if [[ -z "$OBJECTIVE" ]]; then
    emit_error "${WORKER_NAME:-unknown}" "no objective provided (pass --objective or a JSON brief on stdin)"
    exit 2
  fi
}

# build_task_prompt — render the brief into the user-message text.
build_task_prompt() {
  local prompt="OBJECTIVE: $OBJECTIVE"
  [[ -n "$USER_INTENT" ]] && prompt+=$'\n\n'"VERBATIM USER INTENT: $USER_INTENT"
  if [[ ${#BOUNDARIES[@]} -gt 0 ]]; then
    prompt+=$'\n\n'"BOUNDARIES / NON-GOALS:"
    local b; for b in "${BOUNDARIES[@]}"; do prompt+=$'\n'"- $b"; done
  fi
  [[ -n "$OUTPUT_SPEC" ]] && prompt+=$'\n\n'"OUTPUT SPEC (what the result field must contain): $OUTPUT_SPEC"
  [[ -n "$EFFORT_BUDGET" ]] && prompt+=$'\n\n'"EFFORT BUDGET: $EFFORT_BUDGET"
  if [[ ${#INPUT_PATHS[@]} -gt 0 ]]; then
    prompt+=$'\n\n'"INPUT FILES:"
    local p
    for p in "${INPUT_PATHS[@]}"; do
      if [[ -f "$p" ]]; then
        prompt+=$'\n\n'"--- $p ---"$'\n'"$(cat "$p")"
      else
        prompt+=$'\n\n'"--- $p --- (MISSING: file not found; note this in caveats)"
      fi
    done
  fi
  printf '%s' "$prompt"
}

# The envelope instructions appended to every worker's system prompt.
envelope_instructions() {
  local worker="$1"
  cat <<EOF
Respond with ONLY a single JSON object (no markdown fences, no prose before or
after) matching exactly this schema:
{
  "worker": "$worker",
  "status": "ok|partial|error|blocked|needs_escalation|needs_input",
  "summary": "<=100 word digest of what you did and found",
  "result": <content per the OUTPUT SPEC; string or object>,
  "artifacts": [],
  "key_decisions": ["decisions you made that downstream steps must know"],
  "caveats": ["known limitations of this result"],
  "assumptions": ["assumptions you made because the brief did not specify"],
  "confidence_ordinal": "high|medium|low",
  "usage": {"input_tokens": 0, "output_tokens": 0, "est_cost_usd": 0}
}
If the brief is insufficient to proceed, set status to "needs_input" and put
your questions in result. Do not guess. Be terse: output tokens are expensive.
EOF
}

# extract_json_object TEXT — best-effort extraction of a JSON object from model
# output (strips markdown fences if present). Prints JSON or returns 1.
extract_json_object() {
  local text="$1" candidate
  candidate="$(printf '%s' "$text" | sed -e 's/^```json//' -e 's/^```//' -e 's/```$//')"
  if echo "$candidate" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "$candidate"; return 0
  fi
  # Fall back to the substring between the first '{' and last '}'.
  candidate="$(printf '%s' "$text" | sed -n '/{/,$p' | sed -e '1s/^[^{]*//')"
  candidate="${candidate%"${candidate##*\}}"}"
  if echo "$candidate" | jq -e 'type == "object"' >/dev/null 2>&1; then
    echo "$candidate"; return 0
  fi
  return 1
}

# finalize_envelope MODEL_TEXT WORKER IN_TOKENS OUT_TOKENS COST
# Parses the model's envelope, overrides worker/usage with authoritative
# values, writes the artifact if requested, validates, prints.
finalize_envelope() {
  local model_text="$1" worker="$2" in_tok="${3:-0}" out_tok="${4:-0}" cost="${5:-0}"
  local artifacts_json="[]"

  if [[ -n "$ARTIFACT_PATH" ]]; then
    mkdir -p "$(dirname "$ARTIFACT_PATH")"
    printf '%s\n' "$model_text" > "$ARTIFACT_PATH"
    artifacts_json="$(jq -n --arg p "$ARTIFACT_PATH" '[$p]')"
  fi

  local parsed
  if ! parsed="$(extract_json_object "$model_text")"; then
    # Model did not honor the envelope contract — wrap its text.
    jq -n --arg worker "$worker" --arg text "$model_text" \
          --argjson artifacts "$artifacts_json" \
          --argjson in "$in_tok" --argjson out "$out_tok" --argjson cost "$cost" '{
      worker: $worker, status: "partial",
      summary: "worker returned non-JSON output; raw text wrapped in result",
      result: $text, artifacts: $artifacts, key_decisions: [],
      caveats: ["worker did not honor the envelope contract; treat with suspicion"],
      assumptions: [], confidence_ordinal: "low",
      usage: {input_tokens: $in, output_tokens: $out, est_cost_usd: $cost}
    }' | validate_envelope
    return
  fi

  echo "$parsed" | jq --arg worker "$worker" \
      --argjson artifacts "$artifacts_json" \
      --argjson in "$in_tok" --argjson out "$out_tok" --argjson cost "$cost" '
    .worker = $worker
    | .artifacts = ((.artifacts // []) + $artifacts | unique)
    | .key_decisions //= [] | .caveats //= [] | .assumptions //= []
    | .confidence_ordinal //= "medium" | .status //= "ok"
    | .summary //= "" | .result //= null
    | .usage = {input_tokens: $in, output_tokens: $out, est_cost_usd: $cost}
  ' | validate_envelope
}
