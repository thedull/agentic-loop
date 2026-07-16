#!/usr/bin/env bash
# call_fable.sh — single-shot worker call to Claude Fable 5 via the Claude API.
#
# Billing: metered per token on the Claude API, SEPARATE from the Max
# subscription. The key MUST be named FABLE_KEY in ./.env — never
# ANTHROPIC_API_KEY (that would flip the interactive session to API billing).
#
# Usage:
#   ./scripts/call_fable.sh --objective "..." [--user-intent "..."] \
#       [--input-path f.md]... [--boundary "..."]... [--output-spec "..."] \
#       [--effort low|medium|high|xhigh|max] [--artifact .agentic/artifacts/x.md] \
#       [--no-fallback]
#   echo '<brief.json>' | ./scripts/call_fable.sh
#
# Output: one worker envelope JSON on stdout. Non-zero exit on failure.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

WORKER_NAME="fable"
MODEL="claude-fable-5"
MAX_TOKENS=16000
# Pricing as of 2026-07-12: $10 / $50 per 1M tokens in/out. Recalibrate from
# the Anthropic console after real runs.
PRICE_IN_PER_M=10
PRICE_OUT_PER_M=50

load_env
require_key FABLE_KEY "$WORKER_NAME"

parse_brief "$@"

EFFORT="high"
USE_FALLBACK=1
i=0
while [[ $i -lt ${#EXTRA_ARGS[@]} ]]; do
  case "${EXTRA_ARGS[$i]}" in
    --effort)      EFFORT="${EXTRA_ARGS[$((i+1))]}"; i=$((i+2)) ;;
    --no-fallback) USE_FALLBACK=0; i=$((i+1)) ;;
    *) emit_error "$WORKER_NAME" "unknown flag: ${EXTRA_ARGS[$i]}"; exit 2 ;;
  esac
done

case "$EFFORT" in low|medium|high|xhigh|max) ;; *)
  emit_error "$WORKER_NAME" "--effort must be low|medium|high|xhigh|max"; exit 2 ;;
esac

SYSTEM_PROMPT="You are a frontier-quality worker in a multi-model agentic loop. \
Complete the objective exactly as specified. Stay within the stated boundaries. \
Be rigorous and terse.
$(envelope_instructions "$WORKER_NAME")"

TASK_PROMPT="$(build_task_prompt)"

# Fable 5: thinking is always on — omit the thinking parameter entirely.
# Fallback to Opus 4.8 on safety-classifier refusals (server-side beta) is on
# by default; disable with --no-fallback.
REQUEST="$(jq -n \
  --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg task "$TASK_PROMPT" \
  --arg effort "$EFFORT" --argjson max_tokens "$MAX_TOKENS" '{
    model: $model, max_tokens: $max_tokens,
    output_config: {effort: $effort},
    system: [{type: "text", text: $system}],
    messages: [{role: "user", content: $task}]
  }')"

BETA_HEADER=()
if [[ $USE_FALLBACK -eq 1 ]]; then
  REQUEST="$(echo "$REQUEST" | jq '. + {fallbacks: [{model: "claude-opus-4-8"}]}')"
  BETA_HEADER=(-H "anthropic-beta: server-side-fallback-2026-06-01")
fi

if [[ -n "${MOCK_RESPONSE_FILE:-}" ]]; then # test seam (evals/)
  RESPONSE="$(cat "$MOCK_RESPONSE_FILE")"
else
  RESPONSE="$(curl -sS --max-time 900 https://api.anthropic.com/v1/messages \
    -H "content-type: application/json" \
    -H "x-api-key: $FABLE_KEY" \
    -H "anthropic-version: 2023-06-01" \
    "${BETA_HEADER[@]}" \
    -d "$REQUEST")" || { emit_error "$WORKER_NAME" "curl failed reaching the Claude API"; exit 5; }
fi

if echo "$RESPONSE" | jq -e '.type == "error"' >/dev/null 2>&1; then
  emit_error "$WORKER_NAME" "Claude API error: $(echo "$RESPONSE" | jq -r '.error.message')"
  exit 5
fi

STOP_REASON="$(echo "$RESPONSE" | jq -r '.stop_reason // empty')"
if [[ "$STOP_REASON" == "refusal" ]]; then
  emit_error "$WORKER_NAME" "request refused by safety classifiers (category: $(echo "$RESPONSE" | jq -r '.stop_details.category // "unknown"')); fallback chain also refused or was disabled"
  exit 6
fi

MODEL_TEXT="$(echo "$RESPONSE" | jq -r '[.content[] | select(.type == "text") | .text] | join("\n")')"
IN_TOK="$(echo "$RESPONSE" | jq -r '.usage.input_tokens // 0')"
OUT_TOK="$(echo "$RESPONSE" | jq -r '.usage.output_tokens // 0')"
COST="$(jq -n --argjson i "$IN_TOK" --argjson o "$OUT_TOK" \
  --argjson pi "$PRICE_IN_PER_M" --argjson po "$PRICE_OUT_PER_M" \
  '(($i * $pi) + ($o * $po)) / 1000000 * 1000 | round / 1000')"

finalize_envelope "$MODEL_TEXT" "$WORKER_NAME" "$IN_TOK" "$OUT_TOK" "$COST"
