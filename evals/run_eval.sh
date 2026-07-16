#!/usr/bin/env bash
# run_eval.sh — dependency-light eval runner for the agentic-loop plugin.
#
#   ./evals/run_eval.sh                    # free kinds only (bash-unit, mocked
#                                          # shims; judge checks only if local
#                                          # Ollama is up) — always $0
#   ./evals/run_eval.sh --live             # ALSO run headless-agent cases
#                                          # (spawns `claude -p` — draws your
#                                          # subscription/metered quota; same
#                                          # billing caveats as run_headless.sh)
#   ./evals/run_eval.sh --suite envelope   # one suite (cases/envelope/)
#   ./evals/run_eval.sh --case 010-...     # one case by id
#   ./evals/run_eval.sh --judge openrouter # judge tier override (default:
#                                          # ollama if running, else skip)
#
# Case format: evals/README.md. Kinds: bash-unit (run .cmd in a sandbox),
# shim (run a call_*.sh with MOCK_RESPONSE_FILE), headless-agent (run a
# plugin subagent via claude -p; --live only).
# Check types: envelope_valid, jq, exit_code, artifact_exists, must_find,
# tier_expect, judge.
#
# Results: evals/results/results-<ts>.jsonl (gitignored). Exit 1 if any case
# fails; skipped cases do not fail the run.

set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$EVALS_DIR/.." && pwd)"
VALIDATOR="$PLUGIN_ROOT/scripts/lib/validate_envelope.jq"

LIVE=0; SUITE=""; ONLY_CASE=""; JUDGE_TIER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --live)  LIVE=1; shift ;;
    --free)  LIVE=0; shift ;;   # explicit alias of the default
    --suite) SUITE="$2"; shift 2 ;;
    --case)  ONLY_CASE="$2"; shift 2 ;;
    --judge) JUDGE_TIER="$2"; shift 2 ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 3; }

RESULTS_DIR="$EVALS_DIR/results"
mkdir -p "$RESULTS_DIR"
RESULTS="$RESULTS_DIR/results-$(date +%Y%m%d-%H%M%S).jsonl"

PASS=0; FAIL=0; SKIP=0

record() { # id kind status detail_json
  jq -cn --arg id "$1" --arg kind "$2" --arg status "$3" \
         --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson detail "$4" \
    '{ts: $ts, id: $id, kind: $kind, status: $status, detail: $detail}' >> "$RESULTS"
}

run_case() {
  local file="$1" case_json id kind sandbox output="" exit_code=0
  case_json="$(cat "$file")"
  id="$(jq -r '.id' <<<"$case_json")"
  kind="$(jq -r '.kind' <<<"$case_json")"
  [[ -n "$ONLY_CASE" && "$id" != "$ONLY_CASE" ]] && return 0

  sandbox="$(mktemp -d)"

  case "$kind" in
    bash-unit)
      local cmd; cmd="$(jq -r '.cmd' <<<"$case_json")"
      output="$(cd "$sandbox" && AGENTIC_OBSERVE=0 \
                PLUGIN_ROOT="$PLUGIN_ROOT" FIXTURES="$EVALS_DIR/fixtures" \
                bash -c "$cmd" 2>"$sandbox/.stderr")"
      exit_code=$?
      ;;
    shim)
      local shim mock brief
      shim="$(jq -r '.shim' <<<"$case_json")"
      mock="$(jq -r '.mock_response // empty' <<<"$case_json")"
      brief="$(jq -c '.input.brief // {}' <<<"$case_json")"
      local -a args=()
      while IFS= read -r a; do args+=("$a"); done \
        < <(jq -r '(.args // [])[]' <<<"$case_json")
      output="$(cd "$sandbox" && printf '%s' "$brief" \
                | AGENTIC_OBSERVE=0 \
                  MOCK_RESPONSE_FILE="${mock:+$EVALS_DIR/$mock}" \
                  "$PLUGIN_ROOT/scripts/$shim" ${args[@]+"${args[@]}"} \
                  2>"$sandbox/.stderr")"
      exit_code=$?
      ;;
    headless-agent)
      if [[ $LIVE -ne 1 ]]; then
        echo "  [skip] $id (headless-agent — run with --live)"
        SKIP=$((SKIP+1)); record "$id" "$kind" "skip" '{"reason":"needs --live"}'
        rm -rf "$sandbox"; return 0
      fi
      local agent brief prompt raw
      agent="$(jq -r '.agent' <<<"$case_json")"
      # The agent runs in a sandbox cwd: absolutize repo-relative input_paths.
      brief="$(jq -c --arg root "$PLUGIN_ROOT" \
        '.input.brief | (.input_paths // []) |= map(if startswith("/") then . else $root + "/" + . end)' \
        <<<"$case_json")"
      prompt="Execute this delegation brief and end your reply with ONLY the worker envelope JSON (no fences): $brief"
      raw="$(cd "$sandbox" && claude -p "$prompt" --agent "$agent" \
             --output-format json 2>"$sandbox/.stderr")"
      exit_code=$?
      # The envelope is the agent's final text; extract the JSON object.
      output="$(jq -r '.result // empty' <<<"$raw" \
        | AGENTIC_OBSERVE=0 bash -c '
            source "'"$PLUGIN_ROOT"'/scripts/lib/common.sh" 2>/dev/null
            extract_json_object "$(cat)"' 2>/dev/null)" || true
      ;;
    *)
      echo "  [skip] $id (unknown kind '$kind')"
      SKIP=$((SKIP+1)); record "$id" "$kind" "skip" '{"reason":"unknown kind"}'
      rm -rf "$sandbox"; return 0
      ;;
  esac

  # --- checks -----------------------------------------------------------------
  local failed=() skipped=()
  local n; n="$(jq '.checks | length' <<<"$case_json")"
  local i
  for ((i = 0; i < n; i++)); do
    local check ctype ok=1
    check="$(jq -c ".checks[$i]" <<<"$case_json")"
    ctype="$(jq -r '.type' <<<"$check")"
    case "$ctype" in
      envelope_valid)
        printf '%s' "$output" | jq -e -f "$VALIDATOR" >/dev/null 2>&1 || ok=0 ;;
      jq)
        printf '%s' "$output" \
          | jq -e "$(jq -r '.expr' <<<"$check")" >/dev/null 2>&1 || ok=0 ;;
      exit_code)
        if [[ "$(jq -r '.nonzero // false' <<<"$check")" == "true" ]]; then
          [[ "$exit_code" -ne 0 ]] || ok=0
        else
          [[ "$exit_code" -eq "$(jq -r '.equals' <<<"$check")" ]] || ok=0
        fi ;;
      artifact_exists)
        local p all=1
        while IFS= read -r p; do
          [[ -f "$sandbox/$p" || -f "$p" ]] || all=0
        done < <(printf '%s' "$output" \
                 | jq -r "$(jq -r '.paths_from' <<<"$check") // [] | .[]" 2>/dev/null)
        [[ $all -eq 1 ]] || ok=0 ;;
      must_find)
        local needle
        while IFS= read -r needle; do
          printf '%s' "$output" | grep -qiF "$needle" || ok=0
        done < <(jq -r '.strings[]' <<<"$check") ;;
      tier_expect)
        printf '%s' "$output" | jq -e \
          --argjson allowed "$(jq -c '.allowed' <<<"$check")" \
          "[$(jq -r '.path' <<<"$check")] | flatten
           | length > 0 and all(. as \$t | \$allowed | index(\$t) != null)" \
          >/dev/null 2>&1 || ok=0 ;;
      judge)
        local cand score min
        cand="$sandbox/.candidate"
        printf '%s' "$output" > "$cand"
        min="$(jq -r '.min_score // 3' <<<"$check")"
        score="$("$EVALS_DIR/judge.sh" --candidate "$cand" \
                  --rubric "$EVALS_DIR/$(jq -r '.rubric' <<<"$check")" \
                  ${JUDGE_TIER:+--tier "$JUDGE_TIER"} 2>/dev/null \
                 | jq -r '.score // empty')" || score=""
        if [[ -z "$score" ]]; then
          skipped+=("judge (no judge tier available)")
          continue
        fi
        [[ "$score" -ge "$min" ]] || ok=0 ;;
      *) skipped+=("$ctype (unknown check type)"); continue ;;
    esac
    [[ $ok -eq 1 ]] || failed+=("$ctype")
  done

  local detail
  detail="$(jq -cn --argjson ec "$exit_code" \
    --argjson failed "$(printf '%s\n' "${failed[@]+"${failed[@]}"}" | jq -R . | jq -cs 'map(select(. != ""))')" \
    --argjson skipped "$(printf '%s\n' "${skipped[@]+"${skipped[@]}"}" | jq -R . | jq -cs 'map(select(. != ""))')" \
    '{exit_code: $ec, failed_checks: $failed, skipped_checks: $skipped}')"

  if [[ ${#failed[@]} -eq 0 ]]; then
    echo "  [pass] $id${skipped[0]+"  (skipped: ${skipped[*]})"}"
    PASS=$((PASS+1)); record "$id" "$kind" "pass" "$detail"
  else
    echo "  [FAIL] $id — ${failed[*]}"
    [[ -s "$sandbox/.stderr" ]] && sed 's/^/         stderr: /' "$sandbox/.stderr" | head -3
    FAIL=$((FAIL+1)); record "$id" "$kind" "fail" "$detail"
  fi
  rm -rf "$sandbox"
}

echo "agentic-loop evals — $(date '+%Y-%m-%d %H:%M') (live: $LIVE)"
shopt -s nullglob
for dir in "$EVALS_DIR/cases"/*/; do
  name="$(basename "$dir")"
  [[ "$name" == "_inbox" ]] && continue
  [[ -n "$SUITE" && "$name" != "$SUITE" ]] && continue
  files=("$dir"*.json)
  [[ ${#files[@]} -eq 0 ]] && continue
  echo "suite: $name"
  for f in "${files[@]}"; do run_case "$f"; done
done

echo
echo "summary: $PASS pass, $FAIL fail, $SKIP skipped — results: ${RESULTS#"$PLUGIN_ROOT"/}"
[[ $FAIL -eq 0 ]] || exit 1
