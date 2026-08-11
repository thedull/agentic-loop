#!/usr/bin/env bash
# call_sol.sh — best-of-best worker call to Sol (GPT-5.6) via the OpenAI API.
#
# Sol is the EXPENSIVE cross-family adversary/reviser. Call it only on the
# structural triggers in CLAUDE.md, never on a whim. Output costs 6x input
# ($5 / $30 per 1M as of 2026-07-12); hidden reasoning tokens bill as output.
#
# Usage:
#   ./scripts/call_sol.sh --mode adversary --objective "..." \
#       [--input-path candidate.md]... [--effort standard|max|ultra] \
#       [--artifact .agentic/artifacts/sol-review.md]
#   ./scripts/call_sol.sh --mode reviser --objective "..." --input-path full_context.md ...
#
#   --mode adversary  BLIND red-team review. Payload must be ONLY the task +
#                     candidate answer. Do NOT include the orchestrator's
#                     reasoning (anchoring). Findings must cite evidence.
#   --mode reviser    Full-context improvement pass. Include everything.
#   --effort          standard -> reasoning.effort=medium
#                     max      -> reasoning.effort=max
#                     ultra    -> multi-agent beta (parallel subagents; token
#                                 use scales with agent count) + effort=high
#
# Output: one worker envelope JSON on stdout (adversary mode adds findings[]).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

# The name the MODEL is told, and the name the ENVELOPE carries, are deliberately
# two different things. The transport must not leak into the prompt — acceptance
# 4 requires the system prompt to be byte-identical on both paths, and
# envelope_instructions() interpolates whatever name it is given. So prompts are
# always built as "sol"; finalize_envelope overrides .worker afterwards.
PROMPT_WORKER="sol"
WORKER_NAME="sol"
MODEL="gpt-5.6-sol"
# Pricing as of 2026-07-12 (recalibrate from the OpenAI usage dashboard).
# Used ONLY by the direct transport — OpenRouter reports what it actually
# billed, and a figure it did not report is null, never one of these.
PRICE_IN_PER_M=5
PRICE_OUT_PER_M=30

load_env

parse_brief "$@"

MODE="adversary"
EFFORT="standard"
VIA="openai"
BATCH=0
i=0
while [[ $i -lt ${#EXTRA_ARGS[@]} ]]; do
  FLAG="${EXTRA_ARGS[$i]}"
  case "$FLAG" in
    --mode|--effort|--via)
      # Read the value only after confirming there IS one. Indexing past the end
      # under `set -u` aborts with a raw bash error and no envelope at all,
      # which breaks the contract that every failure path emits a status:"error"
      # envelope a caller can parse.
      if [[ $((i+1)) -ge ${#EXTRA_ARGS[@]} ]]; then
        emit_error "$WORKER_NAME" "$FLAG requires a value (nothing followed it)"
        exit 2
      fi
      VAL="${EXTRA_ARGS[$((i+1))]}"
      case "$FLAG" in
        --mode)   MODE="$VAL" ;;
        --effort) EFFORT="$VAL" ;;
        --via)    VIA="$VAL" ;;
      esac
      i=$((i+2)) ;;
    --batch)  BATCH=1; i=$((i+1)) ;;
    --authorize-cost) PREFLIGHT_AUTHORIZED=1; i=$((i+1)) ;;
    *) emit_error "$WORKER_NAME" "unknown flag: $FLAG"; exit 2 ;;
  esac
done

# --- transport selection ------------------------------------------------------
# Never inferred from which keys happen to be present. A project that adds an
# OpenRouter key for bulk work must not silently start billing its Sol calls
# there: an absent key is a failure of the REQUESTED transport, not a reason to
# quietly use the other one.
case "$VIA" in
  openai)
    ENDPOINT="https://api.openai.com/v1/responses"
    ;;
  openrouter)
    WORKER_NAME="sol/openrouter"   # obs_tier_from_worker's sol* glob still maps
    MODEL="openai/gpt-5.6-sol"     # this to the sol tier — obs.sh is untouched
    ENDPOINT="https://openrouter.ai/api/v1/chat/completions"
    ;;
  *)
    emit_error "$WORKER_NAME" "--via must be openai|openrouter (got '$VIA')"
    exit 2 ;;
esac

if [[ $BATCH -eq 1 ]]; then
  if [[ "$VIA" != "openrouter" ]]; then
    emit_error "$WORKER_NAME" "--batch is openrouter-only: ':batch' is an OpenRouter model-id suffix, while OpenAI's batch discount is a separate asynchronous /v1/batches endpoint with a different request lifecycle (out of scope). Retry with --via openrouter."
    exit 2
  fi
  # Opt-in only, never automatic: batch is NOT reliably a discount. On
  # 2026-08-07 z-ai/glm-5.2:batch was priced ABOVE its own non-batch variant,
  # so anything reaching for :batch on its own would sometimes pay more for
  # worse latency. Compare prices before using this.
  MODEL="${MODEL}:batch"
fi



case "$MODE" in
  adversary)
    SYSTEM_PROMPT="You are an independent adversarial reviewer from a different \
model family than the author. You are given ONLY the task and the candidate \
answer — deliberately without the author's reasoning, so you evaluate the \
result on its own terms.
Rules:
- Report ONLY correctness and requirement gaps. Do not report style, taste, or
  hypothetical improvements — chasing those causes over-engineering.
- Proof before preference: for every finding, state the concrete evidence
  (quote, file:line, failing input, or contradiction) BEFORE any verdict.
- If you find nothing that fails the requirements, say so plainly. An empty
  findings list is a valid, useful answer.
- Be terse. Your output tokens are the most expensive in this system.
In your envelope, additionally include:
  \"findings\": [{\"claim\": \"...\", \"evidence\": \"...\", \"severity\": \"high|medium|low\",
                \"location\": {\"file\": \"...\", \"line_start\": N, \"line_end\": N}}]
Every finding MUST carry \"location\". If the finding is about an absence — \
something missing, unhandled or never called — set \"location\": null and add \
\"searched\": \"<the files and scopes you actually examined>\". Do not invent \
line 1 to satisfy the field, and do not report a numeric confidence or score: \
severity is ordinal here. A finding that carries neither a location nor a \
searched scope is rejected on receipt and the whole call is wasted."
    ;;
  reviser)
    SYSTEM_PROMPT="You are a best-of-best reviser in a multi-model agentic loop. \
You are given full context. Produce an improved version of the artifact that \
resolves the stated problems while preserving everything that already works. \
In key_decisions, list every material change you made and why. Be surgical: \
do not rewrite what is not broken. Be terse outside the artifact itself."
    ;;
  *) emit_error "$WORKER_NAME" "--mode must be adversary|reviser"; exit 2 ;;
esac
SYSTEM_PROMPT+="
$(envelope_instructions "$PROMPT_WORKER")"

TASK_PROMPT="$(build_task_prompt)"

REASONING_EFFORT="medium"
MULTI_AGENT=0
case "$EFFORT" in
  standard) REASONING_EFFORT="medium" ;;
  max)      REASONING_EFFORT="max" ;;
  ultra)    REASONING_EFFORT="high"; MULTI_AGENT=1 ;;
  *) emit_error "$WORKER_NAME" "--effort must be standard|max|ultra"; exit 2 ;;
esac

# ultra is a Responses-API capability, not a setting with an equivalent
# elsewhere: it sets a multi_agent field AND an OpenAI-Beta header, and the
# OpenRouter chat/completions body carries no reasoning or effort field at all.
# Refuse rather than downgrade — a flag that silently does less than it says is
# a lie — and do not emulate multi-agent client-side.
if [[ $MULTI_AGENT -eq 1 && "$VIA" != "openai" ]]; then
  emit_error "$WORKER_NAME" "--effort ultra is available only on the direct transport (--via openai): it needs the Responses multi-agent beta, which has no equivalent on OpenRouter. Use --effort max here, or --via openai for ultra."
  exit 2
fi

# Assumed output scales with effort: ultra runs parallel subagents and token use
# scales with agent count (max_concurrent_subagents: 3), so a flat assumption
# would systematically understate the single most expensive path — exactly the
# call this gate exists to catch.
#
# These numbers budget for HIDDEN REASONING, not just visible text, because Sol
# bills reasoning as output (see the header) and — on the chat/completions
# transport — spends it against max_tokens BEFORE emitting a single visible
# character. Measured live 2026-08-10: a cap of 2000 produced 2000 billed output
# tokens and an EMPTY message. The whole budget went to reasoning, the envelope
# never started, and the call was a total loss that still cost $0.074.
#
# That is the same failure the Ollama tier documents for 4B-class models, which
# "spend their whole budget inside <think> and return an empty result" — the
# difference here is only the price.
case "$EFFORT" in
  standard) ASSUMED_OUT=8000 ;;
  max)      ASSUMED_OUT=16000 ;;
  ultra)    ASSUMED_OUT=32000 ;;
  *)        ASSUMED_OUT=8000 ;;
esac
preflight_gate "$WORKER_NAME" "$MODEL" "$SYSTEM_PROMPT$TASK_PROMPT" "$ASSUMED_OUT"

# Credentials are checked AFTER the gate: a call refused on cost must be refused
# before it needs a key, so the refusal is about the spend and not the setup.
case "$VIA" in
  openai)     require_key OPENAI_API_KEY     "$WORKER_NAME" ;;
  openrouter) require_key OPENROUTER_API_KEY "$WORKER_NAME" ;;
esac

if [[ "$VIA" == "openrouter" ]]; then
  # max_tokens is REQUIRED here in practice, even though the Responses API path
  # does fine without it. OpenRouter reserves credit against the provider's
  # default completion ceiling (65536 for this model) when the request does not
  # bound it, so an unbounded call is rejected outright on any key whose limit
  # is below that — for a review that would have used ~2000 tokens.
  #
  # The bound is the SAME number preflight_gate assumed when it printed the
  # estimate. That is what makes the estimate an upper bound rather than a
  # guess, and it is why --effort now changes what the call can actually spend
  # instead of only changing a printed figure.
  #
  # Note the asymmetry, which is real and not an oversight: on THIS transport
  # the assumed output is a hard cap, so the estimate is a ceiling. On the
  # direct Responses API path no max_tokens is sent, so there the same number is
  # an expectation the model may exceed.
  REQUEST="$(jq -n \
    --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg task "$TASK_PROMPT" \
    --argjson max_tokens "$ASSUMED_OUT" '{
      model: $model,
      max_tokens: $max_tokens,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $task}
      ]
    }')"
else
  REQUEST="$(jq -n \
    --arg model "$MODEL" --arg instructions "$SYSTEM_PROMPT" \
    --arg task "$TASK_PROMPT" --arg effort "$REASONING_EFFORT" '{
      model: $model,
      instructions: $instructions,
      input: [{role: "user", content: $task}],
      reasoning: {effort: $effort}
    }')"
fi

# Ask the provider to enforce the finding shape at generation time. This is an
# OPTIMISATION, never the gate: response_format support varies by provider and
# by model, and a gate that stops gating the moment a parameter is dropped is
# not a gate. validate_envelope.jq refuses a malformed finding at receipt
# whether or not this schema was honored.
if [[ "$MODE" == "adversary" ]]; then
  FINDINGS_SCHEMA="$(jq -n '{
        type: "object",
        properties: {
          findings: {
            type: "array",
            items: {
              type: "object",
              required: ["claim", "evidence", "severity", "location"],
              properties: {
                claim:    {type: "string"},
                evidence: {type: "string"},
                severity: {type: "string", enum: ["high", "medium", "low"]},
                location: {anyOf: [
                  {type: "object",
                   required: ["file", "line_start", "line_end"],
                   properties: {
                     file:       {type: "string", minLength: 1},
                     line_start: {type: "integer", minimum: 1},
                     line_end:   {type: "integer", minimum: 1}}},
                  {type: "null"}]},
                searched: {type: "string",
                           description: "required when location is null: the scopes actually examined"}
              }
            }
          }
        }
      }')"
  # Same schema, two wire shapes. The Responses API takes text.format; the
  # OpenRouter chat/completions body takes response_format.json_schema. Sending
  # either shape to the other provider is a field it does not understand, so
  # this branches on transport rather than on hope.
  if [[ "$VIA" == "openrouter" ]]; then
    REQUEST="$(echo "$REQUEST" | jq --argjson schema "$FINDINGS_SCHEMA" '. + {
      response_format: {type: "json_schema",
                        json_schema: {name: "adversary_envelope", strict: false, schema: $schema}}
    }')"
  else
    REQUEST="$(echo "$REQUEST" | jq --argjson schema "$FINDINGS_SCHEMA" '. + {
      text: {format: {type: "json_schema", name: "adversary_envelope",
                      strict: false, schema: $schema}}
    }')"
  fi
fi

BETA_HEADER=()
if [[ $MULTI_AGENT -eq 1 ]]; then
  REQUEST="$(echo "$REQUEST" | jq '. + {multi_agent: {enabled: true, max_concurrent_subagents: 3}}')"
  BETA_HEADER=(-H "OpenAI-Beta: responses_multi_agent=v1")
fi

# Test seam (same spirit as MOCK_RESPONSE_FILE): dump the exact request body so
# an eval can assert on what we send, rather than grepping this file for a
# keyword. Must stay LAST, after every field has been added — dumping earlier
# would let an eval pass on a request the provider never sees. Unset in every
# normal run.
if [[ -n "${SOL_REQUEST_DUMP:-}" ]]; then
  printf '%s' "$REQUEST" > "$SOL_REQUEST_DUMP"
fi

if [[ -n "${MOCK_RESPONSE_FILE:-}" ]]; then # test seam (evals/)
  RESPONSE="$(cat "$MOCK_RESPONSE_FILE")"
elif [[ "$VIA" == "openrouter" ]]; then
  RESPONSE="$(curl -sS --max-time 900 "$ENDPOINT" \
    -H "content-type: application/json" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -d "$REQUEST")" || { emit_error "$WORKER_NAME" "curl failed reaching OpenRouter"; exit 5; }
else
  RESPONSE="$(curl -sS --max-time 900 "$ENDPOINT" \
    -H "content-type: application/json" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    "${BETA_HEADER[@]}" \
    -d "$REQUEST")" || { emit_error "$WORKER_NAME" "curl failed reaching the OpenAI API"; exit 5; }
fi

if echo "$RESPONSE" | jq -e '.error != null' >/dev/null 2>&1; then
  ERR_MSG="$(echo "$RESPONSE" | jq -r '.error.message // .error')"
  if [[ "$VIA" == "openrouter" ]]; then
    emit_error "$WORKER_NAME" "openrouter API error: $ERR_MSG"
    exit 5
  fi
  if [[ $MULTI_AGENT -eq 1 ]]; then
    ERR_MSG+=" (ultra uses the Responses multi-agent beta — if the error names multi_agent, your account may lack beta access; retry with --effort max)"
  fi
  emit_error "$WORKER_NAME" "OpenAI API error: $ERR_MSG"
  exit 5
fi

if [[ "$VIA" == "openrouter" ]]; then
  if [[ "$(echo "$RESPONSE" | jq -r '.choices[0].finish_reason // empty')" == "length" ]]; then
    echo "preflight: WARNING — the response hit the max_tokens cap ($ASSUMED_OUT) and was truncated. The envelope below is likely to be incomplete or non-JSON. Retry with a higher --effort, which raises the cap." >&2
  fi
  MODEL_TEXT="$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')"
  IN_TOK="$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // 0')"
  OUT_TOK="$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // 0')"
  # OpenRouter reports what it actually billed, which beats our own constants.
  # When it reports nothing, the answer is null — NOT 0, and NOT a figure
  # computed from the OpenAI price table above. Substituting either would
  # attribute a number to a source that never produced one, which is exactly
  # what scripts/lib/obs.sh:18-19 exists to prevent.
  COST="$(echo "$RESPONSE" | jq -c '.usage.cost // null')"
else
  # Responses API: output[] contains message items with content[].text parts.
  MODEL_TEXT="$(echo "$RESPONSE" | jq -r '
    [.output[]? | select(.type == "message") | .content[]?
     | select(.type == "output_text") | .text] | join("\n")')"
  [[ -z "$MODEL_TEXT" ]] && MODEL_TEXT="$(echo "$RESPONSE" | jq -r '.output_text // empty')"

  IN_TOK="$(echo "$RESPONSE" | jq -r '.usage.input_tokens // 0')"
  OUT_TOK="$(echo "$RESPONSE" | jq -r '.usage.output_tokens // 0')"
  COST="$(jq -n --argjson i "$IN_TOK" --argjson o "$OUT_TOK" \
    --argjson pi "$PRICE_IN_PER_M" --argjson po "$PRICE_OUT_PER_M" \
    '(($i * $pi) + ($o * $po)) / 1000000 * 1000 | round / 1000')"
fi

finalize_envelope "$MODEL_TEXT" "$WORKER_NAME" "$IN_TOK" "$OUT_TOK" "$COST"
