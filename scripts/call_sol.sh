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

WORKER_NAME="sol"
MODEL="gpt-5.6-sol"
# Pricing as of 2026-07-12 (recalibrate from the OpenAI usage dashboard):
PRICE_IN_PER_M=5
PRICE_OUT_PER_M=30

load_env
require_key OPENAI_API_KEY "$WORKER_NAME"

parse_brief "$@"

MODE="adversary"
EFFORT="standard"
i=0
while [[ $i -lt ${#EXTRA_ARGS[@]} ]]; do
  case "${EXTRA_ARGS[$i]}" in
    --mode)   MODE="${EXTRA_ARGS[$((i+1))]}"; i=$((i+2)) ;;
    --effort) EFFORT="${EXTRA_ARGS[$((i+1))]}"; i=$((i+2)) ;;
    *) emit_error "$WORKER_NAME" "unknown flag: ${EXTRA_ARGS[$i]}"; exit 2 ;;
  esac
done

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
  \"findings\": [{\"claim\": \"...\", \"evidence\": \"...\", \"severity\": \"high|medium|low\"}]"
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
$(envelope_instructions "$WORKER_NAME")"

TASK_PROMPT="$(build_task_prompt)"

REASONING_EFFORT="medium"
MULTI_AGENT=0
case "$EFFORT" in
  standard) REASONING_EFFORT="medium" ;;
  max)      REASONING_EFFORT="max" ;;
  ultra)    REASONING_EFFORT="high"; MULTI_AGENT=1 ;;
  *) emit_error "$WORKER_NAME" "--effort must be standard|max|ultra"; exit 2 ;;
esac

REQUEST="$(jq -n \
  --arg model "$MODEL" --arg instructions "$SYSTEM_PROMPT" \
  --arg task "$TASK_PROMPT" --arg effort "$REASONING_EFFORT" '{
    model: $model,
    instructions: $instructions,
    input: [{role: "user", content: $task}],
    reasoning: {effort: $effort}
  }')"

BETA_HEADER=()
if [[ $MULTI_AGENT -eq 1 ]]; then
  REQUEST="$(echo "$REQUEST" | jq '. + {multi_agent: {enabled: true, max_concurrent_subagents: 3}}')"
  BETA_HEADER=(-H "OpenAI-Beta: responses_multi_agent=v1")
fi

RESPONSE="$(curl -sS --max-time 900 https://api.openai.com/v1/responses \
  -H "content-type: application/json" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  "${BETA_HEADER[@]}" \
  -d "$REQUEST")" || { emit_error "$WORKER_NAME" "curl failed reaching the OpenAI API"; exit 5; }

if echo "$RESPONSE" | jq -e '.error != null' >/dev/null 2>&1; then
  ERR_MSG="$(echo "$RESPONSE" | jq -r '.error.message')"
  if [[ $MULTI_AGENT -eq 1 ]]; then
    ERR_MSG+=" (ultra uses the Responses multi-agent beta — if the error names multi_agent, your account may lack beta access; retry with --effort max)"
  fi
  emit_error "$WORKER_NAME" "OpenAI API error: $ERR_MSG"
  exit 5
fi

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

finalize_envelope "$MODEL_TEXT" "$WORKER_NAME" "$IN_TOK" "$OUT_TOK" "$COST"
