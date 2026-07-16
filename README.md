# agentic-loop

A Claude Code plugin for **orchestrated, multi-model agentic loops**: an
interactive Opus orchestrator (Max subscription) plans and delegates; native
Sonnet/Haiku subagents do subscription-covered work; bash shim scripts reach
Fable 5 (Claude API), Sol/GPT-5.6 (OpenAI), OpenRouter bulk models, and local
Ollama; a bounded cross-family adversarial review gates high-stakes output.

## Tutorial

Open [`docs/tutorial.html`](docs/tutorial.html) in a browser for a step-by-step
walkthrough — from first install (Level 0) through headless runs and
customization (Level 3).

## Install

```bash
claude plugin marketplace add thedull/agentic-loop
claude plugin install agentic-loop@agentic-loop
```

Or from a local checkout, point `marketplace add` at the path instead of the
GitHub slug. For a one-off session without installing:
`claude --plugin-dir /path/to/agentic-loop`

## Instantiate in a project

In any project directory, run `/agentic-loop:init`. It copies the shim
scripts, routing-policy `CLAUDE.md`, `.env.example`, and the `.agentic/`
run-state scaffold into the project, then runs `./scripts/doctor.sh`.
Follow the checklist it prints (fill `.env`, verify subscription login,
dry-run one loop).

## What's in the box

| Piece | What it does |
|---|---|
| `agents/` (plugin-wide) | `loop-planner` (sonnet — decomposition into 6-field briefs), `loop-worker-cheap` (haiku — mechanical), `loop-consolidator` (sonnet — merge + disagreement detection), `loop-reviewer` (sonnet — fresh-context blind review), `loop-frontier` + `loop-reviewer-frontier` (fable — subscription-covered frontier tier, only while your plan includes Fable) |
| `scripts/call_fable.sh` | Fable 5 via Claude API (`FABLE_KEY` — never `ANTHROPIC_API_KEY`) |
| `scripts/call_sol.sh` | Sol/GPT-5.6 via OpenAI Responses API; `--mode adversary\|reviser`, `--effort standard\|max\|ultra` (ultra = multi-agent beta) |
| `scripts/call_openrouter.sh` | Kimi/MiniMax/MiMo or any OpenRouter model |
| `scripts/call_ollama.sh` | free local mechanical worker (default `qwen3.5:4b`) |
| `scripts/run_headless.sh` | gated `claude -p` loop wrapper — read its billing warning |
| `scripts/doctor.sh` | preflight: billing-trap check, keys, tools, envelope self-test, factory checks |
| `templates/CLAUDE.md` | the routing brain: tier ladder, Sol structural triggers, blind-adversary protocol, revision bounds, `.agentic/` coordination rules |
| `skills/spec\|build\|review` + `templates/workflows/factory.js` | **the factory** — morning ideas → unattended spec→build→review pipeline → evening PRs (see below) |
| `scripts/lib/tracker.sh`, `scripts/lib/usage_gate.sh`, `templates/statusline-usage.sh` | factory plumbing: file state machine (connector seam for future GH Issues/Jira backends) + subscription-usage self-gating |
| `hooks/hooks.json` + `scripts/observe.sh` + `scripts/observe_render.sh` | **opt-in observability**: every subagent/shim/headless/factory operation logged to one JSONL (model, tokens, est. cost, duration, status, summary) and rendered as an HTML/tty run tree — `/agentic-loop:config observability on` (see below) |
| `skills/config` | feature flags in `.agentic/config.json`, all default-off: `observability`, `minimize` (code-minimization ladder in build briefs), `grill` (pre-planning interview), `guards` (reviewer quality gates), `summarize` (Ollama report summaries) |
| `evals/` | the plugin's own eval harness: free envelope/shim/tracker/gate suites ($0, mocked), live agent suites behind `--live`, cross-family LLM judge, and `mine.sh` — drafts new eval cases from observability-log failures |

All workers speak one JSON **envelope** (`scripts/lib/validate_envelope.jq`):
`status` enum, ≤100-word `summary`, `result`, `artifacts[]` (full output goes
to files; envelopes carry paths + digests), `key_decisions[]`, `caveats[]`,
`assumptions[]`. Scripts self-validate before returning.

## The Factory

Hand over a list of ideas in the morning; come back in the evening to open,
reviewed PRs. Inspired by [Alex Finn's software-factory workflow](https://x.com/alexfinn/status/2076752798532931758).

1. `/agentic-loop:spec "idea"` (interactive, morning) — adaptive-depth
   grilling → one spec file in `factory/specs/` with a machine-checkable
   `check_cmd`, gated by a fresh-context spec review.
2. `/agentic-loop:build` (unattended) — claims a spec, isolated worktree,
   **Red Gate** (tests must fail first), tier-routed build, `check_cmd` green.
3. `/agentic-loop:review` (unattended) — blind review (security, optimization,
   test quality; findings typed spec/test/impl), bounded revision, conditional
   browser verification with screenshots, opens the PR, writes the evening
   digest to `.agentic/STATUS.md`.

Day mode: install the statusline mirror (usage self-gating: the loop postpones
itself past the cap reset above `FACTORY_USAGE_THRESHOLD`), fill the queue,
then `/loop 60m /factory` in a backgrounded session. Terminal state is always
an **open PR — merging stays yours**, and unattended stages never spend
metered API dollars (`needs_escalation` is queued for your evening decision).

Full guide: [`docs/factory.md`](docs/factory.md) · research companion:
[`docs/software-factory-analysis.md`](docs/software-factory-analysis.md)

## Observability & evals (opt-in)

`/agentic-loop:config observability on`, run your loop, then
`/agentic-loop:config render` — a self-contained HTML tree of the whole
orchestration (per node: tier, model, tokens in/out, est. metered cost,
duration, status, operation summary; rollups split metered $ from
subscription tokens). The flat JSONL under `.agentic/observability/` is the
data-mining substrate: `./evals/mine.sh` turns logged failures into draft
eval cases, and `./evals/run_eval.sh` runs the suites (free tiers always $0).
Reference: [`docs/observability.md`](docs/observability.md) ·
[`evals/README.md`](evals/README.md) · design rationale:
[`docs/observability-evals-analysis.md`](docs/observability-evals-analysis.md)

## Design rationale (why it's built this way)

The design was validated against Anthropic's official guidance, community
harnesses, and the 2025–2026 multi-agent literature (July 2026 review):

- **Bash shims, not MCP wrappers or proxies** — single-shot scripts cost ~80
  prompt tokens instead of tens of thousands of MCP schema tokens, and don't
  degrade tool-calling through protocol translation. Anthropic doesn't support
  non-Claude models in Claude Code; shims treat them as opaque tools.
- **Blind adversary payload** — the reviewer sees only the spec and the
  candidate, never the author's reasoning (anchoring). This is Anthropic's own
  documented review pattern; cross-family review additionally counters
  self/family-preference bias.
- **Structural escalation triggers, never self-reported confidence** —
  verbalized model confidence is the field's most consistent negative result.
- **Bounded revision (hard cap 2, progress-based)** — self-refine gains
  concentrate in rounds 1–2; longer loops degrade and game the critic.
- **Files + git as memory, no memory MCP/DB** — the only controlled benchmark
  of memory in coding agents shows zero quality gain; every credible
  multi-agent system coordinates through files. `.agentic/` is a
  file-blackboard (PLAN/STATUS/decisions/artifacts, single-writer-per-file);
  `LEARNINGS.md` (two-strikes rule, ~300-line cap) carries cross-run lessons;
  native per-subagent `memory: project` does the rest. Graduation paths if you
  outgrow this: Beads (git+SQLite work items) or basic-memory.
- **Frontier review is paired with non-LLM checks** — the most capable models
  converge on the same wrong answers even across providers; tests and
  execution catch what any reviewer misses.

## Billing surfaces (the part that bites)

| Surface | Meter |
|---|---|
| Interactive orchestrator + native subagents | Max subscription (shared 5-hour/weekly caps) |
| `call_fable.sh` | Claude API, metered (`FABLE_KEY`) |
| `call_sol.sh` | OpenAI, metered — output 6x input; reasoning bills as output |
| `call_openrouter.sh` | OpenRouter balance |
| `call_ollama.sh` | free |
| `run_headless.sh` | **different meter than interactive** — read the script's warning |

Never set `ANTHROPIC_API_KEY` in your environment or `.env`: it silently flips
the interactive session from subscription to API billing. `doctor.sh` checks.

**Native Fable tier**: if your plan includes Fable (verified on Max plans
during the July 2026 window), the `loop-frontier` and `loop-reviewer-frontier`
subagents run Fable subscription-covered — prefer them over `call_fable.sh`
while that holds, and revert to the script (metered, explicit spend) when it
doesn't. The routing note in the scaffolded `CLAUDE.md` carries the dated
guidance. Native Fable is same-family: it never substitutes for Sol's
cross-family review.

## Volatile facts — recheck before trusting

Verified 2026-07-12; these move: Sol rate card & the Responses multi-agent
beta, OpenRouter model aliases (override via `.env`), headless billing policy,
subscription caps, plugin packaging conventions.
