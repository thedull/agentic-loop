#!/usr/bin/env bash
# judge.sh — LLM-judge wrapper over the existing worker shims, with the bias
# guards from the judge protocol baked in:
#   - blind provenance: the judge sees only rubric + candidate, never which
#     agent/model produced it
#   - verbosity cap: candidates truncated to 8000 chars before judging, and
#     the rubric objective forbids rewarding length
#   - anchored ordinal scale: scores are 1-4 against per-level rubric anchors,
#     never free-form
#   - tiering: ollama (free) by default when running, else cross-family
#     OpenRouter (pennies). Sol is NEVER auto-selected — explicit --tier sol
#     only, same confirmation ethos as escalation.
#
#   judge.sh --candidate FILE --rubric FILE [--tier ollama|openrouter|sol]
#     → {"score": 1-4, "rationale": "...", "judge_tier": "..."}   (exit 0)
#     exit 4 when no judge tier is available (runner treats as skip)
#
#   judge.sh --compare FILE_A FILE_B --rubric FILE [--tier ...]
#     Position-bias guard for A/B regression comparisons: judges both
#     orderings and reports agreement.
#     → {"first_order": "A|B", "second_order": "A|B", "agree": bool, ...}

set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$EVALS_DIR/.." && pwd)"

CANDIDATE=""; RUBRIC=""; TIER=""; CMP_A=""; CMP_B=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate) CANDIDATE="$2"; shift 2 ;;
    --rubric)    RUBRIC="$2"; shift 2 ;;
    --tier)      TIER="$2"; shift 2 ;;
    --compare)   CMP_A="$2"; CMP_B="$3"; shift 3 ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done
[[ -f "$RUBRIC" ]] || { echo "error: --rubric FILE is required" >&2; exit 2; }

# Tier auto-pick: free first, then cross-family cheap. Never Sol implicitly.
if [[ -z "$TIER" ]]; then
  if curl -sS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    TIER="ollama"
  elif [[ -f ./.env ]] && grep -qE '^\s*OPENROUTER_API_KEY=.+' ./.env; then
    TIER="openrouter"
  else
    echo "error: no judge tier available (start ollama or set OPENROUTER_API_KEY; sol is explicit-only)" >&2
    exit 4
  fi
fi

shim_for_tier() {
  case "$1" in
    ollama)     echo "$PLUGIN_ROOT/scripts/call_ollama.sh" ;;
    openrouter) echo "$PLUGIN_ROOT/scripts/call_openrouter.sh --model kimi" ;;
    sol)        echo "$PLUGIN_ROOT/scripts/call_sol.sh --mode adversary --effort standard" ;;
    *) echo "error: unknown judge tier '$1'" >&2; exit 2 ;;
  esac
}

# judge_once OBJECTIVE OUTPUT_SPEC INPUT_FILES... — one blind shim call.
judge_once() {
  local objective="$1" output_spec="$2"; shift 2
  local -a inputs=()
  local f
  for f in "$@"; do inputs+=(--input-path "$f"); done
  # shellcheck disable=SC2046
  AGENTIC_OBSERVE=0 $(shim_for_tier "$TIER") \
    --objective "$objective" \
    --boundary "You do not know who or what produced the candidate(s); judge only the content" \
    --boundary "Do not reward length; penalize padding" \
    "${inputs[@]}" \
    --output-spec "$output_spec"
}

trunc() { # FILE -> truncated temp copy (verbosity cap)
  local out; out="$(mktemp)"
  head -c 8000 "$1" > "$out"
  printf '%s' "$out"
}

if [[ -n "$CMP_A" ]]; then
  [[ -f "$CMP_A" && -f "$CMP_B" ]] || { echo "error: --compare needs two files" >&2; exit 2; }
  TA="$(trunc "$CMP_A")"; TB="$(trunc "$CMP_B")"; trap 'rm -f "$TA" "$TB"' EXIT
  ask() { # first second -> "FIRST"|"SECOND"
    judge_once \
      "Two candidates follow (FIRST then SECOND). Decide which better satisfies the rubric" \
      'JSON object: {"winner": "FIRST" or "SECOND", "rationale": "<=30 words"}' \
      "$RUBRIC" "$1" "$2" \
      | jq -r 'if .status == "ok" then
                 (.result | if type == "object" then .winner
                  else (tostring | if test("FIRST") then "FIRST"
                        elif test("SECOND") then "SECOND" else empty end) end)
               else empty end'
  }
  R1="$(ask "$TA" "$TB")" || R1=""
  R2="$(ask "$TB" "$TA")" || R2=""
  [[ -n "$R1" && -n "$R2" ]] || { echo "error: judge calls failed" >&2; exit 5; }
  # Map back to A/B per ordering; agreement = same underlying winner.
  W1=$([[ "$R1" == "FIRST" ]] && echo A || echo B)
  W2=$([[ "$R2" == "FIRST" ]] && echo B || echo A)
  jq -cn --arg w1 "$W1" --arg w2 "$W2" --arg tier "$TIER" \
    '{first_order: $w1, second_order: $w2, agree: ($w1 == $w2),
      winner: (if $w1 == $w2 then $w1 else "inconclusive (position bias)" end),
      judge_tier: $tier}'
  exit 0
fi

[[ -f "$CANDIDATE" ]] || { echo "error: --candidate FILE is required" >&2; exit 2; }
TC="$(trunc "$CANDIDATE")"; trap 'rm -f "$TC"' EXIT

ENVELOPE="$(judge_once \
  "Score the CANDIDATE against the RUBRIC using its anchored 1-4 scale" \
  'JSON object: {"score": integer 1-4, "rationale": "<=40 words"}' \
  "$RUBRIC" "$TC")" || { echo "error: judge shim call failed" >&2; exit 5; }

printf '%s' "$ENVELOPE" | jq -ce --arg tier "$TIER" '
  select(.status == "ok" or .status == "partial")
  | (.result | if type == "object" then .
     else (tostring | {score: ([scan("[1-4]")] | first | tonumber?),
                       rationale: .[0:200]}) end)
  | select(.score != null)
  | {score: .score, rationale: (.rationale // null), judge_tier: $tier}' \
  || { echo "error: judge returned no usable score" >&2; exit 5; }
