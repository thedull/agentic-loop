#!/usr/bin/env bash
# doctor.sh — preflight checks for the agentic-loop setup.
# Run from a project directory (where ./.env lives). Safe: read-only.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; WARN=0; FAIL=0
ok()   { echo "  [ok]   $1"; PASS=$((PASS+1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }
fail() { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "agentic-loop doctor — $(date '+%Y-%m-%d %H:%M')"
echo
echo "billing safety:"
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  fail "ANTHROPIC_API_KEY is set in your environment. Claude Code will bill this
         session to the API instead of your Max subscription. Unset it before
         starting interactive sessions (an empty value still wins — truly unset it)."
else
  ok "ANTHROPIC_API_KEY is not set (interactive session stays on subscription auth)"
fi
if [[ -f ./.env ]] && grep -qE '^\s*ANTHROPIC_API_KEY=' ./.env; then
  fail "./.env defines ANTHROPIC_API_KEY — rename it (the Fable worker key must be FABLE_KEY)"
fi

echo
echo "required tools:"
for tool in jq curl; do
  command -v "$tool" >/dev/null 2>&1 && ok "$tool present" || fail "$tool missing"
done
command -v claude >/dev/null 2>&1 && ok "claude CLI present ($(claude --version 2>/dev/null | head -1))" \
  || fail "claude CLI not found"
if command -v ollama >/dev/null 2>&1; then
  ok "ollama present"
  if curl -sS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    ok "ollama server responding on :11434"
  else
    warn "ollama installed but server not responding (run 'ollama serve' or open the app)"
  fi
else
  warn "ollama not installed — local free tier unavailable (call_ollama.sh will fail)"
fi
command -v shellcheck >/dev/null 2>&1 && ok "shellcheck present (optional)" || true

echo
echo "worker keys (./.env):"
if [[ -f ./.env ]]; then
  set -a; source ./.env 2>/dev/null; set +a
  [[ -n "${FABLE_KEY:-}" ]]          && ok "FABLE_KEY set (Fable worker, Claude API metered)" \
                                     || warn "FABLE_KEY missing — call_fable.sh unavailable"
  [[ -n "${OPENAI_API_KEY:-}" ]]     && ok "OPENAI_API_KEY set (Sol worker, OpenAI metered)" \
                                     || warn "OPENAI_API_KEY missing — call_sol.sh unavailable"
  [[ -n "${OPENROUTER_API_KEY:-}" ]] && ok "OPENROUTER_API_KEY set (bulk workers)" \
                                     || warn "OPENROUTER_API_KEY missing — call_openrouter.sh unavailable"
else
  warn "./.env not found — copy .env.example to .env and fill in the keys you have"
fi
if [[ -f ./.gitignore ]] && grep -qE '(^|/)\.env$' ./.gitignore; then
  ok ".env is gitignored"
elif [[ -d ./.git ]]; then
  fail ".env is NOT in .gitignore — keys would be committed"
fi

echo
echo "envelope validator self-test:"
VALID='{"worker":"test","status":"ok","summary":"s","result":"r","artifacts":[],"key_decisions":[],"caveats":[],"assumptions":[],"confidence_ordinal":"high","usage":{"input_tokens":1,"output_tokens":1,"est_cost_usd":0}}'
INVALID='{"worker":"test","status":"nonsense","summary":"s"}'
if echo "$VALID" | jq -e -f "$SCRIPT_DIR/lib/validate_envelope.jq" >/dev/null 2>&1; then
  ok "valid envelope accepted"
else
  fail "valid envelope REJECTED — validate_envelope.jq is broken"
fi
if echo "$INVALID" | jq -e -f "$SCRIPT_DIR/lib/validate_envelope.jq" >/dev/null 2>&1; then
  fail "invalid envelope ACCEPTED — validate_envelope.jq is broken"
else
  ok "invalid envelope rejected"
fi

echo
echo "factory (skip if you don't use the spec→build→review loop):"
if [[ -d ./factory/specs ]]; then
  [[ -x ./scripts/lib/tracker.sh ]] && ok "tracker.sh present" \
    || fail "factory/specs exists but scripts/lib/tracker.sh is missing/not executable — re-run /agentic-loop:init"
  [[ -x ./scripts/lib/usage_gate.sh ]] && ok "usage_gate.sh present" \
    || fail "scripts/lib/usage_gate.sh missing — usage gating unavailable"
  if [[ -f ./.claude/settings.json ]] && grep -q 'statusline-usage' ./.claude/settings.json 2>/dev/null; then
    ok "statusline usage mirror configured"
  else
    warn "statusline usage mirror not configured — the usage gate will fail open.
         Add to .claude/settings.json:
         {\"statusLine\": {\"type\": \"command\", \"command\": \"scripts/statusline-usage.sh\"}}"
  fi
  if [[ -f ./.agentic/usage.json ]]; then
    AGE_MIN=$(( ($(date +%s) - $(jq -r '.mirrored_at // 0' ./.agentic/usage.json 2>/dev/null || echo 0)) / 60 ))
    [[ $AGE_MIN -le "${FACTORY_USAGE_STALE_MINUTES:-120}" ]] \
      && ok "usage mirror fresh (${AGE_MIN}min old)" \
      || warn "usage mirror stale (${AGE_MIN}min old) — gate fails open until a live session refreshes it"
  else
    warn "no .agentic/usage.json yet — appears after the first turn of a session with the statusline installed"
  fi
else
  ok "no factory/specs directory (factory not initialized here)"
fi

echo
echo "observability (opt-in):"
if [[ "$(jq -r '.observability.enabled // false' ./.agentic/config.json 2>/dev/null)" == "true" ]]; then
  ok "observability enabled (.agentic/config.json)"
  LATEST_EVENTS="$(ls -t ./.agentic/observability/events-*.jsonl 2>/dev/null | head -1)"
  if [[ -n "$LATEST_EVENTS" ]]; then
    if tail -1 "$LATEST_EVENTS" | jq -e '.v == 1' >/dev/null 2>&1; then
      ok "event log healthy ($(wc -l < "$LATEST_EVENTS" | tr -d ' ') events in ${LATEST_EVENTS#./})"
    else
      warn "last line of ${LATEST_EVENTS#./} is not a v1 event — log may be corrupted"
    fi
  else
    warn "enabled but no events yet — they appear after the first instrumented run"
  fi
else
  ok "observability disabled — opt in with /agentic-loop:config observability on"
fi

echo
echo "subscription auth (manual check):"
echo "  Run 'claude' interactively and confirm the session shows your Max"
echo "  subscription login (claude /login), not an API key. This script cannot"
echo "  verify login mode from outside a session."

echo
echo "summary: $PASS ok, $WARN warnings, $FAIL failures"
[[ $FAIL -eq 0 ]] || exit 1
