# agentic-loop — Handoff Brief

**Prepared:** 2026-07-13
**Status:** Built and verified. Ready to install and use; a few keyed/interactive steps remain (§8).
**For:** Anyone adopting this template — human or a fresh Claude session. This document is self-contained.

---

## 0. How to use this document

If you were handed this repo, read §1–§3 to understand what it is, §7 to install it, and §8 for what's deliberately left to you. §4–§6 are the design rationale and the research evidence behind it — read those before changing anything, so you don't accidentally relitigate a decision the evidence already settled. §10 lists the volatile facts to re-verify before trusting them.

---

## 1. What this is

A **Claude Code plugin** (`agentic-loop`) implementing a repeatable, orchestrated, multi-model agentic loop you can instantiate in any project folder:

- An **interactive Opus orchestrator** (your Max subscription session) plans, delegates, validates, consolidates, and decides on escalation. It does no domain work itself.
- **Native subagents** (Sonnet/Haiku, subscription-covered) do the planning support, mechanical work, consolidation, and routine review.
- **Bash shim scripts** reach the non-Claude tiers: Sol (GPT-5.6, OpenAI API), Fable 5 (Claude API, metered), OpenRouter bulk models, and free local Ollama.
- A **bounded cross-family adversarial review** (Sol as blind red-teamer) gates high-stakes output.
- All workers speak one strict **JSON envelope**, validated with jq; full outputs go to files, envelopes carry paths + digests.

The point of the multi-surface design is economics + epistemics: lean hard on the subscription, pay metered rates only for frontier cross-family review, and use a different model family to catch the correlated errors same-family review misses.

## 2. The cast and their billing surfaces

Keeping these straight is central. Each tier sits on a different meter:

| Role | Model | Reached via | Meter |
|---|---|---|---|
| Orchestrator | Opus (interactive Claude Code) | you, in a session | Max subscription |
| Planner / consolidator / reviewer | Sonnet | native subagents (`loop-*`) | subscription (shared caps) |
| Mechanical worker | Haiku | native subagent | subscription |
| Frontier second-family | Fable 5 | `scripts/call_fable.sh` | Claude API, metered (`FABLE_KEY`) |
| Best-of-best adversary/reviser | Sol (GPT-5.6) | `scripts/call_sol.sh` | OpenAI, metered — output 6x input |
| Cheap bulk | Kimi / MiniMax / MiMo | `scripts/call_openrouter.sh` | OpenRouter balance |
| Free mechanical | local (default qwen3.5:4b) | `scripts/call_ollama.sh` | free |

**The two billing traps, both guarded by tooling:**
1. **Never set `ANTHROPIC_API_KEY`** (env or `.env`) — it silently flips the interactive session from subscription to metered API billing. The Fable worker key is deliberately named `FABLE_KEY`. `scripts/doctor.sh` checks for this.
2. **Headless runs (`claude -p`) are metered differently** from interactive. `scripts/run_headless.sh` refuses to run without `--i-understand-billing`, a prompt-spec file, and a real completion-check command.

## 3. The loop (as encoded in `templates/CLAUDE.md`)

1. **Plan** — `loop-planner` decomposes into subtasks, each with a **6-field brief**: objective, verbatim user intent (anti-telephone-game), input paths (never inlined content), boundaries/non-goals, output spec, effort budget. Tier assigned per subtask.
2. **Fan out** to the cheapest adequate tier; parallel only when subtasks are independent.
3. **Validate every return**: check envelope `status`, verify claimed `artifacts[]` exist on disk (workers claiming unwritten work is a documented failure mode), carry forward `key_decisions`/`caveats`/`assumptions`.
4. **Consolidate** — `loop-consolidator` merges; worker **disagreement is recorded, never forced into consensus** — it's an escalation signal.
5. **Routine review** — `loop-reviewer`: a fresh-context, subscription-covered blind reviewer. Runs executable checks where they exist.
6. **Escalate to Sol** only on **structural triggers** (high-stakes/irreversible; material disagreement; known-hard class; repeated schema/worker failure; tests failing post-revision) — never on anyone's felt or self-reported confidence. The human confirms before every Sol call and the final ship.
7. **Revise, bounded**: one round; +1 only if the artifact materially changed and a check still fails; hard cap 2; then ship-with-caveats or surface to the human.

Coordination substrate is **files, not context**: `.agentic/PLAN.md` (recited/updated; survives compaction), `STATUS.md`, `decisions.md` (append-only; all workers read it before acting), `artifacts/` (single-writer-per-file). Cross-run lessons in a committed `LEARNINGS.md` (two-strikes rule, ~300-line cap). **No memory MCP/DB anywhere** — see §5.

## 4. Repo layout

```
agentic-scaffolding/            (plugin root)
├── .claude-plugin/plugin.json  name: agentic-loop
├── agents/                     plugin-wide subagents (registered wherever enabled)
│   ├── planner.md              sonnet, memory:project — decomposition into 6-field briefs
│   ├── worker-cheap.md         haiku, maxTurns:15 — mechanical only
│   ├── consolidator.md         sonnet, memory:project — merge + disagreement detection
│   ├── reviewer.md             sonnet, read+test tools, memory:project — blind review
│   ├── frontier.md             fable — frontier tier, subscription-covered ONLY while plan includes Fable
│   └── reviewer-frontier.md    fable — pre-Sol blind review, same window caveat
├── skills/init/SKILL.md        /agentic-loop:init — copies scripts+templates into a project
├── scripts/
│   ├── lib/common.sh           .env loading, brief parsing, envelope build/validate
│   ├── lib/validate_envelope.jq
│   ├── call_sol.sh             --mode adversary|reviser, --effort standard|max|ultra
│   ├── call_fable.sh           FABLE_KEY; refusal handling; Opus fallback (--no-fallback)
│   ├── call_openrouter.sh      --model kimi|minimax|mimo|<full id>
│   ├── call_ollama.sh          local, default qwen3.5:4b
│   ├── run_headless.sh         gated claude -p loop (Ralph-style: file state, check-cmd, caps)
│   └── doctor.sh               preflight + envelope self-test
├── templates/                  copied per-project by init
│   ├── CLAUDE.md               THE ROUTING BRAIN — read this first
│   ├── .env.example, gitignore-snippet, LEARNINGS.md, PROJECT_README.md
│   ├── hooks-spawn-guard.json  opt-in PreToolUse spawn-budget cap
│   └── agentic-state/          .agentic/ scaffold (PLAN/STATUS/decisions/artifacts)
├── README.md                   install + rationale summary
└── HANDOFF.md                  this file
```

Distribution model: **agents live in the plugin** (available in every project where it's enabled); **scripts + CLAUDE.md + state dirs are copied per-project** by init, because `${CLAUDE_PLUGIN_ROOT}` doesn't resolve inside markdown — copies keep projects self-contained with stable paths.

## 5. Design decisions and the evidence behind them

The design was stress-tested against three research sweeps (July 2026): Anthropic's official corpus, community harnesses, and the 2025–2026 multi-agent literature. Don't undo these without new evidence:

- **Bash shims, not MCP wrappers or `ANTHROPIC_BASE_URL` proxies**, for non-Claude models. Shims cost ~80 prompt tokens vs tens of thousands of MCP schema tokens; proxies degrade tool-calling through protocol translation. Anthropic explicitly doesn't support non-Claude models in Claude Code — shims treat them as opaque tools, which is the honest framing.
- **Blind adversary payload** (task + candidate only, author's reasoning withheld) — literally Anthropic's documented reviewer pattern; validated by anchoring research (Refute-or-Promote, Cross-Context Review). Cross-family review counters measured self/family-preference bias. Two-phase option: reveal rationale after the blind pass for confirm/withdraw.
- **Structural escalation triggers, never verbalized confidence** — the field's most consistent negative result: model self-reported confidence saturates high and correlates weakly with correctness.
- **Revision hard cap 2, progress-based** — self-refine gains concentrate in rounds 1–2; longer loops degrade output and reward-hack the critic.
- **Frontier review paired with non-LLM checks** (tests, execution) — ICML 2025: the most capable models converge on the *same wrong answers* even across providers. Cross-family review reduces but does not eliminate shared blind spots.
- **Files + git as memory; no memory MCP/DB** — the only controlled benchmark of memory in coding agents (Mar 2026) shows zero quality gain and net harm on small projects; every credible multi-agent system (Anthropic harnesses, Gas Town, Ralph loops, HumanLayer) coordinates through files. Bonus: shim workers read files for free, MCP would need plumbing per model family. Graduation paths if outgrown: Beads (git+SQLite work items) or basic-memory.
- **~79% of multi-agent failures are spec/coordination** (MAST, NeurIPS 2025) — hence the fixed 6-field brief, artifact-existence verification, single-writer-per-file, and the append-only decisions log.
- **Rejected**: swarm frameworks (token-hungry; 3–8 sharply-scoped agents beat 100-agent collections), unbounded debate (sycophantic convergence), agent teams as foundation (still experimental — built on stable subagents instead).

## 6. The worker envelope (the contract everything speaks)

```json
{ "worker": "sol|fable|openrouter/<m>|ollama/<m>|haiku|sonnet",
  "status": "ok|partial|error|blocked|needs_escalation|needs_input",
  "summary": "<=100 word digest",
  "result": "<per the brief's output_spec>",
  "artifacts": ["paths to full outputs — orchestrator verifies existence"],
  "key_decisions": [], "caveats": [], "assumptions": [],
  "confidence_ordinal": "high|medium|low  (ordinal per-worker; never an escalation trigger)",
  "usage": {"input_tokens": 0, "output_tokens": 0, "est_cost_usd": 0} }
```
Reviewers add `findings[]`, each `{claim, evidence, severity}` — evidence required before verdict. Scripts self-validate against `scripts/lib/validate_envelope.jq` and emit a structured `status:"error"` envelope + non-zero exit on any failure. `needs_input` is the escape hatch: under-briefed workers ask instead of guessing.

## 7. Install and instantiate

```bash
claude plugin marketplace add thedull/agentic-loop
claude plugin install agentic-loop@agentic-loop
# then, inside any project:
/agentic-loop:init
cp .env.example .env        # fill FABLE_KEY / OPENAI_API_KEY / OPENROUTER_API_KEY (any subset)
./scripts/doctor.sh          # fix FAILs; verify subscription login interactively
```
Dry-run: give the orchestrator a small task and watch plan → delegate → consolidate → review. Per-project checklist lands as `AGENTIC_LOOP.md`.

## 8. Verified vs left-to-do

**Verified (2026-07-13):** all scripts syntax-clean; envelope validator 8/8 accept/reject cases; keyless runs of all metered scripts return clean structured errors; **live end-to-end run against local qwen3.5:4b produced a correct, schema-valid envelope with artifact written**; all four headless gates fire; doctor passes; init copy steps executed verbatim into a scratch dir produced a working scaffold.

**Deliberately left to the adopter:** the interactive `/plugin` install (can't be driven from outside a session); 1-call keyed smoke tests of Fable/Sol/OpenRouter (small metered cost); a live `claude -p --plugin-dir` load test (skipped on principle — it bills on the headless meter this design treats as opt-in).

## 9. Known open threads

1. **Native `model: fable` subagents** are shipped as `loop-frontier` (drafting/hard reasoning) and `loop-reviewer-frontier` (pre-Sol blind review) — subscription-covered **only while the plan includes Fable** (verified 2026-07-13 on the author's Max plan; window ends ~2026-07-17). The scaffolded CLAUDE.md carries dated routing guidance: prefer them during the window, revert to `call_fable.sh` (metered) after. Same-family — never a substitute for Sol's cross-family review. Re-check whether your own plan includes Fable before relying on this tier.
2. **Sol `--effort ultra`** uses the OpenAI Responses multi-agent beta (`OpenAI-Beta: responses_multi_agent=v1`); if an account lacks beta access the script says so and suggests `--effort max`.
3. ~~High-fan-out/repeatable loops should graduate to a native workflow script — no workflow template ships yet.~~ **Closed 2026-07-14**: the factory ships this — `templates/workflows/factory.js` plus the `spec`/`build`/`review` skills, `scripts/lib/tracker.sh` (file state machine over `factory/specs/`, with a documented connector seam for future GitHub Issues/Jira backends), and `scripts/lib/usage_gate.sh` + `templates/statusline-usage.sh` (subscription-usage self-gating). See `docs/factory.md` (guide) and `docs/software-factory-analysis.md` (research). v2 roadmap lives in the guide: auto-merge babysitting, headless `--queue` mode, tracker adapters, `profile: hardened` tooling.
4. The spawn-guard hook is opt-in and crude (60s window, count cap) — good enough as a runaway backstop, not a scheduler.

## 10. Freshness / provenance

Product facts verified **2026-07-12/13** against live Anthropic docs (code.claude.com), OpenAI docs (GPT-5.6 Sol pages), and primary research sources. **Volatile — re-verify before hard-coding into changes:** Sol rate card ($5/$30 per 1M as of writing) and the multi-agent beta; OpenRouter model aliases (overridable via `.env`); subscription usage caps; plugin packaging conventions. **Headless billing — resolved 2026-07-14** (costs.md): billing follows the auth method, not headless-ness — plain `claude -p` under OAuth draws the subscription; `--bare` requires `ANTHROPIC_API_KEY` (API metering); Routines draw subscription usage. `run_headless.sh`'s gate stays (the `--bare`/API-key trap is real). Cost calibration numbers in `templates/CLAUDE.md` carry as-of dates — recalibrate from your usage dashboards after the first real runs.
