#!/usr/bin/env bash
# call_ollama.sh — free local worker call via Ollama.
#
# Low judgment: mechanical tasks only (extraction, formatting, simple
# classification, high-volume lookups). Never route judgment-bearing work here.
#
# Usage:
#   ./scripts/call_ollama.sh --objective "..." [-m qwen3.5:4b] \
#       [--input-path f.md]... [--artifact .agentic/artifacts/x.md]
#
# Default model: OLLAMA_MODEL from ./.env, else qwen3.5:4b.
# Output: one worker envelope JSON on stdout.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/common.sh"

command -v ollama >/dev/null 2>&1 || { emit_error "ollama" "ollama is not installed (https://ollama.com)"; exit 3; }

load_env
parse_brief "$@"

MODEL="${OLLAMA_MODEL:-qwen3.5:4b}"
i=0
while [[ $i -lt ${#EXTRA_ARGS[@]} ]]; do
  case "${EXTRA_ARGS[$i]}" in
    -m|--model) MODEL="${EXTRA_ARGS[$((i+1))]}"; i=$((i+2)) ;;
    *) emit_error "ollama" "unknown flag: ${EXTRA_ARGS[$i]}"; exit 2 ;;
  esac
done
WORKER_NAME="ollama/$MODEL"

SYSTEM_PROMPT="You are a mechanical worker. Complete the objective exactly as \
specified. Do not add commentary or judgment beyond what is asked.
$(envelope_instructions "$WORKER_NAME")"

TASK_PROMPT="$(build_task_prompt)"

REQUEST="$(jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg task "$TASK_PROMPT" '{
  model: $model, stream: false,
  messages: [
    {role: "system", content: $system},
    {role: "user", content: $task}
  ]
}')"

RESPONSE="$(curl -sS --max-time 600 http://localhost:11434/api/chat \
  -H "content-type: application/json" \
  -d "$REQUEST")" || { emit_error "$WORKER_NAME" "curl failed reaching the local Ollama server (is 'ollama serve' running?)"; exit 5; }

if echo "$RESPONSE" | jq -e '.error != null' >/dev/null 2>&1; then
  emit_error "$WORKER_NAME" "Ollama error: $(echo "$RESPONSE" | jq -r '.error')"
  exit 5
fi

MODEL_TEXT="$(echo "$RESPONSE" | jq -r '.message.content // empty')"
# Some local models emit <think>...</think> blocks — strip them before parsing.
MODEL_TEXT="$(printf '%s' "$MODEL_TEXT" | sed -e ':a' -e 's/<think>.*<\/think>//g' -e '/<think>/{N;ba' -e '}')"
IN_TOK="$(echo "$RESPONSE" | jq -r '.prompt_eval_count // 0')"
OUT_TOK="$(echo "$RESPONSE" | jq -r '.eval_count // 0')"

finalize_envelope "$MODEL_TEXT" "$WORKER_NAME" "$IN_TOK" "$OUT_TOK" 0
