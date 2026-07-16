#!/usr/bin/env bash
# call_openrouter.sh — cheap bulk worker call via OpenRouter.
#
# Billing: OpenRouter balance (list price + top-up fee, no per-token markup).
#
# Usage:
#   ./scripts/call_openrouter.sh --model kimi --objective "..." \
#       [--input-path f.md]... [--artifact .agentic/artifacts/x.md]
#
#   --model  alias (kimi | minimax | mimo) or any full OpenRouter model id
#            (e.g. moonshotai/kimi-k2). Aliases are defined below and can be
#            overridden in ./.env via OPENROUTER_MODEL_<ALIAS>.
#
# Output: one worker envelope JSON on stdout.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

load_env
require_key OPENROUTER_API_KEY "openrouter"

parse_brief "$@"

MODEL_ARG=""
i=0
while [[ $i -lt ${#EXTRA_ARGS[@]} ]]; do
  case "${EXTRA_ARGS[$i]}" in
    --model) MODEL_ARG="${EXTRA_ARGS[$((i+1))]}"; i=$((i+2)) ;;
    *) emit_error "openrouter" "unknown flag: ${EXTRA_ARGS[$i]}"; exit 2 ;;
  esac
done
[[ -z "$MODEL_ARG" ]] && { emit_error "openrouter" "--model is required (kimi|minimax|mimo or a full OpenRouter id)"; exit 2; }

# Alias table — override in .env (e.g. OPENROUTER_MODEL_KIMI=moonshotai/kimi-k3)
# if these ids go stale.
case "$MODEL_ARG" in
  kimi)    MODEL="${OPENROUTER_MODEL_KIMI:-moonshotai/kimi-k2}" ;;
  minimax) MODEL="${OPENROUTER_MODEL_MINIMAX:-minimax/minimax-m2}" ;;
  mimo)    MODEL="${OPENROUTER_MODEL_MIMO:-xiaomi/mimo-v2}" ;;
  *)       MODEL="$MODEL_ARG" ;;
esac
WORKER_NAME="openrouter/$MODEL"

SYSTEM_PROMPT="You are a bulk worker in a multi-model agentic loop. Complete \
the objective exactly as specified; stay within the boundaries; do not \
editorialize.
$(envelope_instructions "$WORKER_NAME")"

TASK_PROMPT="$(build_task_prompt)"

REQUEST="$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg task "$TASK_PROMPT" '{
  model: $model,
  messages: [
    {role: "system", content: $system},
    {role: "user", content: $task}
  ]
}')"

if [[ -n "${MOCK_RESPONSE_FILE:-}" ]]; then # test seam (evals/)
  RESPONSE="$(cat "$MOCK_RESPONSE_FILE")"
else
  RESPONSE="$(curl -sS --max-time 600 https://openrouter.ai/api/v1/chat/completions \
    -H "content-type: application/json" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    -d "$REQUEST")" || { emit_error "$WORKER_NAME" "curl failed reaching OpenRouter"; exit 5; }
fi

if echo "$RESPONSE" | jq -e '.error != null' >/dev/null 2>&1; then
  emit_error "$WORKER_NAME" "OpenRouter error: $(echo "$RESPONSE" | jq -r '.error.message // .error')"
  exit 5
fi

MODEL_TEXT="$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')"
IN_TOK="$(echo "$RESPONSE" | jq -r '.usage.prompt_tokens // 0')"
OUT_TOK="$(echo "$RESPONSE" | jq -r '.usage.completion_tokens // 0')"
# OpenRouter reports actual cost when available; fall back to 0.
COST="$(echo "$RESPONSE" | jq -r '.usage.cost // 0')"

finalize_envelope "$MODEL_TEXT" "$WORKER_NAME" "$IN_TOK" "$OUT_TOK" "$COST"
