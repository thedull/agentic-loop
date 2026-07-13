# Agentic Loop — project setup checklist

This project was scaffolded by `/agentic-loop:init`. Before the first run:

1. **Keys**: `cp .env.example .env` and fill in the keys you have
   (`FABLE_KEY`, `OPENAI_API_KEY`, `OPENROUTER_API_KEY`). Skip any you don't
   use — the corresponding script will fail cleanly.
2. **Never** set `ANTHROPIC_API_KEY` anywhere (shell or .env) — it flips your
   interactive Claude Code session from Max-subscription billing to metered
   API billing.
3. **Auth**: start `claude` and confirm you're logged in via the Max
   subscription (`/login`), not an API key.
4. **Preflight**: `./scripts/doctor.sh` — fix any FAIL lines.
5. **Dry run one loop**: give the orchestrator a small task, e.g.
   "Use the loop to summarize the three largest files in this repo" — watch it
   plan (loop-planner), delegate (call_ollama.sh / loop-worker-cheap),
   consolidate (loop-consolidator), and review (loop-reviewer).
6. **Optional keyed smoke tests** (1 short call each, small metered cost):
   ```bash
   ./scripts/call_fable.sh --objective "Reply with the word ok" --output-spec "the word ok"
   ./scripts/call_sol.sh --mode reviser --effort standard --objective "Reply with the word ok"
   ./scripts/call_openrouter.sh --model kimi --objective "Reply with the word ok"
   ```
7. **Optional hardening**: merge `hooks-spawn-guard.json` into
   `.claude/settings.json` to cap runaway subagent fan-out.

How the loop works, tier routing, and escalation rules: see `CLAUDE.md`.
Headless (unattended) runs: read the billing warning at the top of
`scripts/run_headless.sh` first — headless usage is metered differently from
your interactive Max session.
