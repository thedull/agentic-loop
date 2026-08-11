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
# Reads KEY=value lines from ./.env (project cwd). Ignores comments and blank
# lines. Values are set in THIS process only and deliberately not exported, so
# no child process — subagent, eval sandbox, hook — inherits a credential.
#
# Parsed as DATA, never sourced. `source ./.env` ran the file as shell, which
# broke two contracts at once: a stray `echo` landed on stdout ahead of the
# envelope (stdout is supposed to carry exactly one envelope and nothing else),
# and any command in the file executed with the shim's privileges — from a file
# that ships with scaffolded projects. Both reproduced 2026-08-11.
#
# The old comment claimed it did "NOT export to children"; `set -a` did exactly
# that. The comment is now true because the code changed, not the wording.
load_env() {
  [[ -f ./.env ]] || return 0
  local line k v
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"                                  # tolerate CRLF
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    line="${line#"${line%%[![:space:]]*}"}"                # ltrim
    [[ "$line" == export[[:space:]]* ]] && line="${line#export}" &&       line="${line#"${line%%[![:space:]]*}"}"
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"; v="${line#*=}"
    k="${k%"${k##*[![:space:]]}"}"                         # rtrim the key
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue     # ignore junk lines
    # Strip one matching pair of surrounding quotes, the common .env idiom.
    if [[ "$v" == \"*\" && ${#v} -ge 2 ]]; then v="${v:1:${#v}-2}"
    elif [[ "$v" == \'*\' && ${#v} -ge 2 ]]; then v="${v:1:${#v}-2}"; fi
    printf -v "$k" '%s' "$v"                               # set, do NOT export
  done < ./.env
  return 0
}

# require_key VAR_NAME worker_label — fail with a structured error envelope if unset.
# Test seam: mocked runs (MOCK_RESPONSE_FILE set, used by evals/) need no keys.
require_key() {
  [[ -n "${MOCK_RESPONSE_FILE:-}" ]] && return 0
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
# The documented <=100 word summary limit, surfaced as a WARNING and never as a
# refusal. It is the only stylistic rule in a validator that is otherwise all
# structure and types, and refusing here would discard a complete answer that has
# already been paid for — on a metered tier that is real money destroyed to
# enforce prose length. Reported so drift is visible; the envelope still ships.
_warn_long_summary() {
  local words
  words="$(printf '%s' "$1" | jq -r '.summary // ""' 2>/dev/null | wc -w | tr -d ' ')"
  [[ "$words" =~ ^[0-9]+$ ]] || return 0
  if [[ "$words" -gt 100 ]]; then
    echo "envelope: summary is ${words} words; the contract is <=100 (see envelope_instructions above and agents/reviewer.md). Not refused — the call is already paid for — but the evening digest is built from these." >&2
  fi
  return 0
}

validate_envelope() {
  local env_json
  env_json="$(cat)"
  _warn_long_summary "$env_json"
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
      # Validate BEFORE destructuring. These assignments run under the shims'
      # `set -e`, so a parse failure aborted the process mid-way and stdout
      # stayed empty — no envelope at all, from a library whose contract is that
      # every failure path emits a parseable status:"error" one.
      if ! printf '%s' "$brief" | jq -e 'type == "object"' >/dev/null 2>&1; then
        emit_error "${WORKER_NAME:-unknown}" "the brief on stdin is not a JSON object. Pass a JSON brief, or use --objective and the other flags."
        exit 2
      fi
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
    # Every value-taking flag is checked for its value first. Reading $2 when it
    # does not exist aborts under `set -u` with a raw bash message and no
    # envelope — the same defect found the same day in tracker.sh's claim edges
    # and observe.sh's argument loops. Three occurrences of one habit.
    case "$1" in
      --objective|--user-intent|--input-path|--boundary|--output-spec|--effort-budget|--artifact)
        if [[ $# -lt 2 ]]; then
          emit_error "${WORKER_NAME:-unknown}" "$1 requires a value (nothing followed it)"
          exit 2
        fi ;;
    esac
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
    # Findings have ONE home: the top level of the envelope. Every declaration
    # already says so — envelope_instructions, agents/reviewer.md, the response
    # schema in call_sol.sh — but models legitimately read otherwise, because
    # envelope_instructions also says `result` holds "content per the OUTPUT
    # SPEC" and every adversary brief sets output_spec to "findings". The first
    # live adversary call answered with result.findings and three separate
    # readers saw nothing: the validator (fixed in #18), observe.sh
    # findings_count, and the comprehension metric built on it.
    #
    # Normalising HERE, at the one boundary every worker passes through, is why
    # this is a fix rather than a fourth patch: downstream readers get one shape
    # and never need to know the model drifted.
    (if (((.findings // []) | length) == 0)
        and ((.result | type) == "object")
        and ((.result.findings | type) == "array")
       then .findings = .result.findings | .result |= del(.findings)
       else . end)
    | .worker = $worker
    | .artifacts = ((.artifacts // []) + $artifacts | unique)
    | .key_decisions //= [] | .caveats //= [] | .assumptions //= []
    | .confidence_ordinal //= "medium" | .status //= "ok"
    | .summary //= "" | .result //= null
    | .usage = {input_tokens: $in, output_tokens: $out, est_cost_usd: $cost}
  ' | validate_envelope
}

# --- pre-flight cost gate -----------------------------------------------------
# "The human confirms all metered spend" exists in seven places as prose with
# nothing enforcing it. This is the enforcement: every metered shim prints what
# the call is expected to cost BEFORE issuing it, and refuses above a threshold
# unless explicitly authorized.
#
# Two rules that look like details and are not:
#   1. The estimate NEVER reaches usage.est_cost_usd. That field is reserved for
#      what a provider actually reported (obs.sh:17-19 — "never fabricate tokens
#      or costs a source did not report"). An estimate written there would be
#      indistinguishable from a billed figure for the rest of the log's life.
#   2. A broken threshold refuses. A gate that reads a garbage config and
#      concludes "no limit" is worse than no gate, because it looks like one.

PREFLIGHT_DEFAULT_THRESHOLD_USD="1.00"
PREFLIGHT_EXIT_REFUSED=7      # distinct: 2 bad flag, 3 missing tool, 4 schema,
                              # 5 transport, 6 provider refusal, 7 cost gate
PREFLIGHT_BYTES_PER_TOKEN=4   # documented heuristic; see preflight_estimate_tokens

# preflight_price MODEL — prints "IN_PER_M OUT_PER_M", or returns 1 if unpriced.
# Committed table, deliberately NOT a live lookup: a network round-trip before
# every call trades the thing being protected (cost) for latency and a new
# failure mode. The staleness is the accepted trade — the OpenRouter catalog
# moved 34% on one model within a single day on 2026-08-07.
# Sourced from docs/codex-subscription.md §7.1 (snapshot 2026-08-07) and the
# per-shim constants in call_sol.sh / call_fable.sh.
preflight_price() {
  case "$1" in
    gpt-5.6-sol-pro|openai/gpt-5.6-sol-pro) echo "5 30" ;;
    openai/gpt-5.6-sol-pro:batch)   echo "2.50 15" ;;
    gpt-5.6-sol|openai/gpt-5.6-sol) echo "5 30" ;;
    openai/gpt-5.6-sol:batch)       echo "2.50 15" ;;
    claude-fable-5)                 echo "10 50" ;;
    moonshotai/kimi-k3)             echo "3.00 15.00" ;;
    qwen/qwen3.8-max)               echo "2.00 6.00" ;;
    z-ai/glm-5.2)                   echo "0.5026 1.5796" ;;
    z-ai/glm-5.2:batch)             echo "0.70 2.20" ;;
    minimax/minimax-m3)             echo "0.30 1.20" ;;
    deepseek/deepseek-v4-flash)     echo "0.14 0.28" ;;
    deepseek/deepseek-v4-pro)       echo "0.435 0.87" ;;
    xiaomi/mimo-v2.5)               echo "0.14 0.28" ;;
    xiaomi/mimo-v2.5-pro)           echo "0.435 0.87" ;;
    *) return 1 ;;
  esac
}

# preflight_estimate_tokens TEXT — bytes/4, rounded up. An approximation, and
# labelled as one everywhere it is reported. It is deterministic, which is the
# property that actually matters here: the same brief must always produce the
# same threshold decision, or the gate is a coin flip.
#
# BYTES, not characters, and deliberately so. `${#var}` counts characters under
# a UTF-8 locale and bytes otherwise, which would make the same prompt estimate
# differently on two machines and a threshold decision non-reproducible across
# environments. `local LC_ALL=C` pins it to bytes everywhere. Bytes are also the
# better proxy: a multibyte character is usually MORE than one token, not fewer,
# so counting characters would understate non-ASCII prompts.
preflight_estimate_tokens() {
  local LC_ALL=C
  local n=${#1}
  echo $(( (n + PREFLIGHT_BYTES_PER_TOKEN - 1) / PREFLIGHT_BYTES_PER_TOKEN ))
}

# emit_blocked WORKER MESSAGE — a refusal envelope. Distinct from emit_error:
# nothing went wrong, the call was declined before it was made.
emit_blocked() {
  jq -n --arg worker "$1" --arg msg "$2" '{
    worker: $worker, status: "blocked", summary: $msg, result: null,
    artifacts: [], key_decisions: [], caveats: [], assumptions: [],
    confidence_ordinal: "high",
    usage: {input_tokens: 0, output_tokens: 0, est_cost_usd: null}
  }' | obs_shim_tap
}

# preflight_gate WORKER MODEL PROMPT_TEXT ASSUMED_OUT_TOKENS
# Prints the estimate to stderr (never stdout — that belongs to the envelope),
# then either returns 0 or refuses with exit 7.
#
# HOW MUCH THIS NUMBER IS WORTH, stated precisely because the whole point of the
# line is to be trusted:
#   output — bounded on the OpenRouter transport, where ASSUMED_OUT is sent as
#            max_tokens. An expectation on the direct Responses path, which
#            sends no cap.
#   input  — an ESTIMATE, never a bound, on every transport. Measured
#            2026-08-10: openai/gpt-5.6-sol-pro billed 18,759 input tokens on a
#            prompt this heuristic put at 1,983 — 9.5x over — because a
#            multi-pass model re-bills context on each internal pass. The call
#            still came in under its estimate, but only because output landed
#            below the cap; had output hit the cap the true cost ($0.574) would
#            have EXCEEDED the printed estimate ($0.490).
# So this is a useful forecast and a hard gate, but calling it an upper bound
# would be a false assurance in the one place designed to be believed.
preflight_gate() {
  local worker="$1" model="$2" text="$3" assumed_out="$4"
  local in_tok cost_str cost_exact price p_in p_out priced=1 authorized=0 thr raw

  in_tok="$(preflight_estimate_tokens "$text")"

  if price="$(preflight_price "$model")"; then
    p_in="${price% *}"; p_out="${price#* }"
    # Two figures on purpose: a rounded one to PRINT, and the exact one to
    # COMPARE. Rounding before the comparison lets an estimate below 0.00005
    # read as 0.0000 and slip under a smaller threshold. Not reachable with
    # today's price table and the 2000-token assumed-output floor — the cheapest
    # possible estimate is ~0.00056 — but the gate should not depend on that
    # staying true.
    cost_str="$(awk -v i="$in_tok" -v o="$assumed_out" -v pi="$p_in" -v po="$p_out" \
      'BEGIN{printf "%.4f", (i*pi + o*po)/1000000}')"
    cost_exact="$(awk -v i="$in_tok" -v o="$assumed_out" -v pi="$p_in" -v po="$p_out" \
      'BEGIN{printf "%.12f", (i*pi + o*po)/1000000}')"
  else
    priced=0; cost_str=""; p_in="?"; p_out="?"
  fi

  # Authorization is EXPLICIT only. Never inferred from a TTY, from an
  # interactive session, or from the absence of a CI variable — the unattended
  # path is precisely the one nobody is watching, and inferring intent there
  # would leave it ungated.
  if [[ "${FACTORY_COST_AUTHORIZED:-}" == "1" || "${PREFLIGHT_AUTHORIZED:-0}" == "1" ]]; then
    authorized=1
  fi

  # Resolve the threshold for reporting. UNSET means "no configuration" and gets
  # the documented default; SET-BUT-BROKEN (empty, negative, non-numeric) is a
  # different thing entirely and must not read as "no limit".
  local thr_valid=1
  if [[ -z "${FACTORY_COST_THRESHOLD_USD+x}" ]]; then
    thr="$PREFLIGHT_DEFAULT_THRESHOLD_USD"
  else
    raw="$FACTORY_COST_THRESHOLD_USD"
    if [[ "$raw" == "off" ]]; then
      thr="off"
    elif [[ "$raw" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
      thr="$raw"
    else
      thr="$raw"; thr_valid=0
    fi
  fi

  # The line. Always printed, on every metered call, whatever happens next.
  local line="preflight: estimated cost "
  if [[ $priced -eq 1 ]]; then line+="${cost_str} USD"; else line+="UNKNOWN (no committed price)"; fi
  line+=" for ${model} — estimate only, never recorded as a cost."
  line+=" Method: input ESTIMATED at ${in_tok} tokens by bytes/${PREFLIGHT_BYTES_PER_TOKEN}"
  line+=" (not capped — a multi-pass model re-bills context and can exceed this)"
  line+=" + output assumed ${assumed_out} tokens"
  line+=" at ${p_in}/${p_out} USD per 1M. threshold ${thr} USD"
  [[ $authorized -eq 1 ]] && line+=" — AUTHORIZED explicitly, gate bypassed"
  printf '%s\n' "$line" >&2

  # Mocked runs spend nothing. Mirrors require_key's existing exemption at :58.
  [[ -n "${MOCK_RESPONSE_FILE:-}" ]] && return 0
  [[ $authorized -eq 1 ]] && return 0

  if [[ $thr_valid -eq 0 ]]; then
    emit_blocked "$worker" "refusing: FACTORY_COST_THRESHOLD_USD is '${raw}', which is not a number or the sentinel 'off'. A threshold that cannot be read must not be treated as no limit. Set a number, or 'off' to disable the gate (note: 0 keeps its literal meaning and refuses everything)."
    exit $PREFLIGHT_EXIT_REFUSED
  fi

  if [[ $priced -eq 0 ]]; then
    emit_blocked "$worker" "refusing: no committed price for model '${model}', so the cost of this call is unknown — an unpriced model is a reason to ask, not a reason to bill blind. Estimated ${in_tok} input + ${assumed_out} assumed output tokens. Add it to preflight_price() in scripts/lib/common.sh, or pass --authorize-cost / FACTORY_COST_AUTHORIZED=1 to proceed anyway."
    exit $PREFLIGHT_EXIT_REFUSED
  fi

  [[ "$thr" == "off" ]] && return 0

  if [[ "$(awk -v c="${cost_exact:-$cost_str}" -v t="$thr" 'BEGIN{print (c+0 >= t+0) ? 1 : 0}')" == "1" ]]; then
    emit_blocked "$worker" "refusing: estimated ${cost_str} USD is at or above the threshold ${thr} USD, and this call was not explicitly authorized. Nothing was sent. Pass --authorize-cost (or FACTORY_COST_AUTHORIZED=1) to make the spend a decision, or raise FACTORY_COST_THRESHOLD_USD."
    exit $PREFLIGHT_EXIT_REFUSED
  fi
  return 0
}
