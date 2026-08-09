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
    # Which model the worker will ACTUALLY use, resolved the same way
    # call_ollama.sh resolves it (./.env, else the shim default).
    OLLAMA_PICK="$(grep -m1 '^OLLAMA_MODEL=' ./.env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'')"
    [[ -n "$OLLAMA_PICK" ]] || OLLAMA_PICK="qwen3.5:4b"
    OLLAMA_HAVE="$(curl -sS --max-time 2 http://localhost:11434/api/tags 2>/dev/null \
                   | jq -r '.models[]?.name' 2>/dev/null)"
    if ! grep -qxF "$OLLAMA_PICK" <<<"$OLLAMA_HAVE"; then
      warn "OLLAMA_MODEL='$OLLAMA_PICK' is not pulled — 'ollama pull $OLLAMA_PICK', or set OLLAMA_MODEL in ./.env to one you have"
    # Measured, not assumed: a 4B-class model spends its whole budget inside
    # <think> and returns an empty result the shim correctly reports as
    # `partial` — a wasted call that looks like a tier failure. Observed on
    # both boxes; every project here had to override the shipped default by
    # hand, which is the definition of a trap worth gating rather than
    # documenting.
    # Parse the size numerically — a digit-pattern match reads "12b" as
    # "1" and flags a 12B model as tiny. Handles 4b / 0.8b / e4b ("effective
    # 4B", which behaves like one).
    elif OLLAMA_SIZE="${OLLAMA_PICK##*:}"; OLLAMA_SIZE="${OLLAMA_SIZE%[bB]}"; \
         OLLAMA_SIZE="${OLLAMA_SIZE#[eE]}"; \
         awk -v s="$OLLAMA_SIZE" 'BEGIN{exit !(s+0 > 0 && s+0 <= 4)}' 2>/dev/null; then
      warn "OLLAMA_MODEL='$OLLAMA_PICK' is 4B-class — these return status 'partial' with an empty result (budget spent in <think>). Prefer a larger non-thinking model, e.g. gemma4:12b"
    else
      ok "ollama worker model '$OLLAMA_PICK' pulled and not 4B-class"
    fi
  else
    warn "ollama installed but server not responding (run 'ollama serve' or open the app)"
  fi
else
  warn "ollama not installed — local free tier unavailable (call_ollama.sh will fail)"
fi
echo
echo "cross-run memory:"
if [[ -f ./LEARNINGS.md ]]; then
  if out="$("$(dirname "${BASH_SOURCE[0]}")/lib/learnings.sh" check ./LEARNINGS.md 2>&1)"; then
    ok "${out#learnings: }"
  else
    warn "${out#learnings: }"
  fi
else
  ok "no LEARNINGS.md yet (created on the first recorded lesson)"
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
echo "scaffold version:"
SCAFFOLD="$SCRIPT_DIR/lib/scaffold.sh"
if [[ -f ./.claude-plugin/plugin.json ]]; then
  # This IS the plugin source, not a project scaffolded from it. Comparing it
  # against an installed copy would report "drift" backwards and confuse.
  ok "this is the agentic-loop source tree itself (v$(jq -r '.version // "?"' ./.claude-plugin/plugin.json 2>/dev/null)) — nothing to update"
elif [[ -f "$SCAFFOLD" ]]; then
  STAMPED="$(bash "$SCAFFOLD" version 2>/dev/null)"
  PROOT="$(bash "$SCAFFOLD" plugin-root 2>/dev/null)"
  if [[ -z "$STAMPED" ]]; then
    warn "no scaffold stamp — this project predates version stamping.
         Run /agentic-loop:update to record one and pick up newer plugin files."
  else
    ok "scaffolded from agentic-loop v$STAMPED"
  fi
  # Local edits to plugin-owned files (needs no plugin install to answer).
  EDITED="$(bash "$SCAFFOLD" integrity 2>/dev/null)"
  if [[ -n "$EDITED" ]]; then
    warn "plugin-owned files differ from the last recorded install (hand-edited,
         or copied in without re-stamping) — /agentic-loop:update reconciles
         them and asks before replacing anything:
$(echo "$EDITED" | sed 's/^/           /')"
  fi
  # Version drift against a discoverable install.
  if [[ -n "$PROOT" ]]; then
    PVER="$(jq -r '.version // empty' "$PROOT/.claude-plugin/plugin.json" 2>/dev/null)"
    SUM="$(bash "$SCAFFOLD" summary "$PROOT" 2>/dev/null)"
    NEEDS=$(( $(echo "$SUM" | jq -r '.stale // 0') \
            + $(echo "$SUM" | jq -r '.unverified // 0') \
            + $(echo "$SUM" | jq -r '.missing // 0') ))
    if [[ "$NEEDS" -gt 0 ]]; then
      warn "scaffold drift vs installed plugin v${PVER:-?}: $SUM
         Run /agentic-loop:update to refresh plugin-owned files."
    else
      ok "scaffold matches installed plugin v${PVER:-?}"
    fi
    if [[ -n "$STAMPED" && -n "$PVER" && "$STAMPED" != "$PVER" ]]; then
      warn "stamped v$STAMPED, installed plugin is v$PVER"
    fi
  else
    warn "no agentic-loop install found — cannot compare against upstream
         (set AGENTIC_PLUGIN_ROOT, or run doctor from a session with the plugin loaded)"
  fi
else
  warn "scripts/lib/scaffold.sh missing — scaffold version tracking unavailable"
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
echo "review benches (opt-in):"
if [[ "$(jq -r '.bench.enabled // false' ./.agentic/config.json 2>/dev/null)" == "true" ]]; then
  ok "bench enabled (.agentic/config.json)"
  [[ -x ./scripts/lib/bench.sh ]] && ok "bench.sh present" \
    || fail "bench enabled but scripts/lib/bench.sh is missing/not executable — re-run /agentic-loop:init"
  BENCH_DIR="$(jq -r '.bench.dir // empty' ./.agentic/config.json 2>/dev/null)"
  [[ -n "$BENCH_DIR" ]] || BENCH_DIR="../$(basename "$PWD")-benches"
  if [[ -d "$BENCH_DIR" ]]; then
    ok "bench dir exists ($BENCH_DIR, $(ls -1 "$BENCH_DIR" 2>/dev/null | wc -l | tr -d ' ') bench(es))"
  else
    warn "bench dir not created yet ($BENCH_DIR) — appears after the first reconcile with a pr-open spec"
  fi
else
  ok "bench disabled — opt in with /agentic-loop:config bench on"
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
    # Propagation health: of the leaf events inside phase_start..phase_end
    # windows, how many carry phase/spec_id? Low % = a skill is claiming
    # without `observe.sh context set`, or clearing early.
    CTX_STATS="$(cat ./.agentic/observability/events-*.jsonl 2>/dev/null | jq -cs '
      [.[] | select(.event | IN("shim_call","agent_stop","headless_iteration"))]
      | {leaves: length, tagged: ([.[] | select(.phase != null)] | length)}' 2>/dev/null)"
    CTX_LEAVES="$(jq -r '.leaves // 0' <<<"$CTX_STATS" 2>/dev/null)"
    CTX_TAGGED="$(jq -r '.tagged // 0' <<<"$CTX_STATS" 2>/dev/null)"
    HAS_PHASES="$(cat ./.agentic/observability/events-*.jsonl 2>/dev/null \
      | jq -s '[.[] | select(.event == "phase_start")] | length > 0' 2>/dev/null)"
    if [[ "$HAS_PHASES" == "true" && "$CTX_LEAVES" -gt 0 ]]; then
      if [[ "$CTX_TAGGED" -gt 0 ]]; then
        ok "stage context propagating ($CTX_TAGGED/$CTX_LEAVES leaf events carry phase/spec_id)"
      else
        warn "phase markers exist but no leaf event carries phase/spec_id — a skill may be clearing context before delegating"
      fi
    fi
    # Stale context files (crash between set and clear): harmless past the
    # TTL, but worth surfacing so the operator knows a stage died mid-run.
    STALE_CTX="$(find ./.agentic/observability/state -name 'ctx-*.json' -mmin +30 2>/dev/null | wc -l | tr -d ' ')"
    [[ "${STALE_CTX:-0}" -gt 0 ]] \
      && warn "$STALE_CTX stale stage-context file(s) in .agentic/observability/state — a stage exited without 'observe.sh context clear' (safe to delete)"
    # Retention nudge — pruning is manual by design (never during a run).
    LIVE_DAYS="$(ls ./.agentic/observability/events-*.jsonl 2>/dev/null | wc -l | tr -d ' ')"
    REPORT_COUNT="$(ls ./.agentic/observability/reports/*.html 2>/dev/null | wc -l | tr -d ' ')"
    [[ "${LIVE_DAYS:-0}" -gt 30 || "${REPORT_COUNT:-0}" -gt 20 ]] \
      && warn "log growing ($LIVE_DAYS event day-files, $REPORT_COUNT reports) — run ./scripts/observe_prune.sh (gzips events, caps reports; readers handle .gz)"
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
