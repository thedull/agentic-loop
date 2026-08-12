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

**Keeping a project current.** Those copies do not update themselves — a
project scaffolded at 0.6.0 never gains anything shipped later unless you
say so. `/agentic-loop:update` refreshes the plugin-owned files (the shims,
`scripts/lib/*`, `doctor.sh`, the factory workflow and spec template) and
leaves everything the project owns alone. It records a committed stamp at
`scripts/.agentic-scaffold.json` — version, project type, and a checksum per
file — so it can tell a stale copy from one you deliberately edited, and asks
before overwriting the latter. `./scripts/doctor.sh` reports the drift.

> Two drift axes, not one: `/agentic-loop:update` copies from your
> **installed** plugin, so run `claude plugin update agentic-loop` first —
> otherwise you faithfully update a project to a version that is itself
> behind. The skill prints the root and version it copied from for exactly
> this reason.

## What's in the box

| Piece | What it does |
|---|---|
| `agents/` (plugin-wide) | `loop-planner` (sonnet — decomposition into 6-field briefs), `loop-worker-cheap` (haiku — mechanical), `loop-consolidator` (sonnet — merge + disagreement detection), `loop-reviewer` (sonnet — fresh-context blind review), `loop-frontier` + `loop-reviewer-frontier` (fable — subscription-covered frontier tier, only while your plan includes Fable) |
| `scripts/call_fable.sh` | Fable 5 via Claude API (`FABLE_KEY` — never `ANTHROPIC_API_KEY`) |
| `scripts/call_sol.sh` | Sol/GPT-5.6, two transports that reach **different model tiers**: `--via openai` (Responses API, default) resolves `gpt-5.6-sol` — OpenAI exposes no `-pro` variant — while `--via openrouter` resolves `openai/gpt-5.6-sol-pro` (`--batch` available there, never automatic). Both overridable via `OPENAI_MODEL_SOL` / `OPENROUTER_MODEL_SOL`. `--mode adversary\|reviser`, `--effort standard\|max\|ultra` (ultra is direct-transport only — it needs the multi-agent beta, which OpenRouter has no equivalent for, so it refuses rather than silently downgrading) |
| `scripts/call_openrouter.sh` | Kimi/MiniMax/MiMo or any OpenRouter model — a model with no entry in the committed price table **refuses** rather than billing blind |
| `scripts/call_ollama.sh` | free local mechanical worker (default `qwen3.5:4b`) |
| `scripts/run_headless.sh` | gated `claude -p` loop wrapper — read its billing warning |
| `scripts/doctor.sh` | preflight: billing-trap check, keys, tools, envelope self-test, scaffold-drift + factory checks |
| `skills/update` + `scripts/lib/scaffold.sh` | **the update path**: enumerated manifest of plugin-owned files, committed version stamp with per-file checksums, and `/agentic-loop:update` — refreshes a project's scaffold without touching anything the project owns. Refuses to run against a live factory (a held claim + a swapped `tracker.sh` = a half-applied state machine) |
| `skills/line` + `scripts/lib/workflow.sh` | **the loop builder**: your production line is your file, but plugin-owned *regions* inside it keep updating. Customize the line without forking it — and without losing safety policy by omission |
| `skills/shelve` | **the off-ramps** (`/agentic-loop:shelve`): take a spec out of the queue as `shelved` (deprioritized, reversible) or `superseded` (landed some other way) instead of lying with `done`/`blocked` — then repair every dependency chain the removal strands. `superseded` unblocks dependents only against a citation git can verify, and `report` grows a `stalled:` column so a dead chain stops looking like one that's merely in progress ([docs](docs/factory.md#deprioritizing-a-spec)) |
| `scripts/lib/bench.sh` | **review benches** (opt-in): one persistent, `origin/main`-merged, set-up checkout per open PR, because hands-on review often means *running* the thing, not reading a diff. Reconciled mechanically every iteration, never by an agent remembering to |
| `templates/CLAUDE.md` | the routing brain: tier ladder, Sol structural triggers, blind-adversary protocol, revision bounds, `.agentic/` coordination rules |
| `skills/spec\|build\|review` + `templates/workflows/factory.js` | **the factory** — morning ideas → unattended spec→build→review pipeline → evening PRs (see below) |
| `scripts/lib/tracker.sh`, `scripts/lib/usage_gate.sh`, `templates/statusline-usage.sh` | factory plumbing: file state machine (connector seam for future GH Issues/Jira backends) + subscription-usage self-gating |
| `hooks/hooks.json` + `scripts/observe.sh` + `scripts/observe_render.sh` | **opt-in observability**: every subagent/shim/headless/factory operation logged to one JSONL (model, tokens, est. cost, duration, status, summary) and rendered as an HTML/tty run tree — `/agentic-loop:config observability on` (see below) |
| `skills/config` | feature flags in `.agentic/config.json`, all default-off: `observability`, `minimize` (code-minimization ladder in build briefs), `grill` (pre-planning interview; `grill deep` adds glossary/ADR deep interviews via grill-with-docs when installed), `guards` (reviewer quality gates), `summarize` (Ollama report summaries) |
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
   `check_cmd`, gated by a fresh-context spec review. Coupled ideas record
   `depends_on:` so they cannot be built before their dependency is merged.
2. `/agentic-loop:build` (unattended) — claims a spec whose dependencies are
   all `done`, isolated worktree, **Red Gate** (tests must fail first),
   tier-routed build, `check_cmd` green.
3. `/agentic-loop:review` (unattended) — blind review (security, optimization,
   test quality; findings typed spec/test/impl), bounded revision, conditional
   browser verification with screenshots, opens the PR **with a mandatory test
   plan** — copy-pasteable commands, one checkbox per acceptance criterion,
   and an explicit *what could not be verified here* section — then writes the
   evening digest to `.agentic/STATUS.md`.

Day mode: install the statusline mirror (usage self-gating: the loop postpones
itself past the cap reset above `FACTORY_USAGE_THRESHOLD`), fill the queue,
then `/loop 60m /factory` in a backgrounded session. Terminal state is always
an **open PR — merging stays yours**, and unattended stages never spend
metered API dollars (`needs_escalation` is queued for your evening decision).

**No two production lines are identical.** `.claude/workflows/factory.js` is
*your* file — sequencing, extra stages, machine realities (a port that must
stay up, a package-manager quirk). The spans marked `owner=plugin` inside it
are the exception: they hold the stage contracts and safety policy, and
`/agentic-loop:update` refreshes them in place. So customizing your line no
longer costs you upstream improvements.

That split came from a real failure. A project needed a different line, had no
seam, and forked the workflow — and the fork silently dropped the review
stage's *record `needs_escalation`* rule and pinned a skill path to a plugin
version that had since moved. **Forking loses policy by omission.** Region
ownership makes that structurally impossible: a hand-edit inside a plugin
region is detected and refused rather than quietly overwritten, and
`/agentic-loop:line` adds your customization in the right place for you.

Full guide: [`docs/factory.md`](docs/factory.md) · research companion:
[`docs/software-factory-analysis.md`](docs/software-factory-analysis.md) ·
graded against an outside rubric:
[`docs/osmani-audit.md`](docs/osmani-audit.md) — Addy Osmani's light/dark
factories essay and his 24-skill catalog, versus what we actually built (four
gaps, a ranked adoption backlog, and a specified-but-unbuilt dark merge lane) ·
tier economics: [`docs/codex-subscription.md`](docs/codex-subscription.md) —
whether a ChatGPT subscription can fund Sol via OpenAI's Codex plugin, and why
an unmetered Sol quietly voids a safety rule this repo states in seven places ·
what the first real cross-family review found:
[`docs/hardening-2026-08.md`](docs/hardening-2026-08.md) — seventeen PRs, 22
defects in our own core (three of them safety gates that had never once fired),
the two failures no mocked test could reach, and the three recurring mistakes
behind most of them · does a cross-family adversary earn its cost?
[`docs/field-reports/2026-08-11-sol-reviews/`](docs/field-reports/2026-08-11-sol-reviews/)
— all five raw GPT-5.6 Sol envelopes, verbatim and unreproducible: 19 findings,
19 confirmed real, zero false positives, against code already green at 300+
tests, plus where it was imprecise and how flat compares to Pro on identical
input

## Observability & evals (opt-in)

`/agentic-loop:config observability on`, run your loop, then
`/agentic-loop:config render` — a self-contained HTML tree of the whole
orchestration (per node: tier, model, tokens in/out, est. metered cost,
duration, status, operation summary; rollups split metered $ from
subscription tokens). Every event carries `phase`/`spec_id`, so
`./scripts/observe_metrics.sh` answers the questions that matter: spend by
stage, tokens/errors/re-opens per spec, two-segment cycle time, and a
per-effort-budget estimation table. `observe_prune.sh` keeps the log
bounded (gzip, lossless), and the opt-in `observability stack` exports to
a local OpenObserve for phone-reachable dashboards
([architecture & comparison](docs/observability-architecture.md)). The flat
JSONL under `.agentic/observability/` is the data-mining substrate:
`./evals/mine.sh` turns logged failures into draft eval cases, and
`./evals/run_eval.sh` runs the suites (free tiers always $0).
Reference: [`docs/observability.md`](docs/observability.md) ·
[`evals/README.md`](evals/README.md) · design rationale:
[`docs/observability-evals-analysis.md`](docs/observability-evals-analysis.md) ·
architecture, metrics & roadmap:
[`docs/observability-architecture.md`](docs/observability-architecture.md)

## Design rationale (why it's built this way)

Three principles came out of running this on real projects rather than from
the literature, and they now decide most design arguments here:

- **Gates, not documentation.** The "use a non-thinking Ollama model" trap was
  written up in the runbook, `.env.example`, *and* a gotcha table — and still
  bit two of three projects. Prose does not prevent; a check that refuses
  does. Hence `depends_on` gating claims, `doctor.sh` refusing a leaked API
  key, and update refusing a live factory.
- **Reconcile, don't remember.** A step an agent is told to perform is a step
  it will eventually skip — one did, which is why open PRs had no bench to
  test from. State the invariant instead ("every open PR has a fresh bench")
  and repair it mechanically every iteration; a run that forgets is fixed by
  the next one.
- **Ownership must be sub-file, or people fork.** Whole-file ownership forces
  a choice between customizing your line and ever receiving an update. One
  project forked, and the fork silently lost a safety rule. Marked regions
  make the split explicit and the loss impossible.

The rest was validated against Anthropic's official guidance, community
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
| `call_sol.sh` | OpenAI **or** OpenRouter, metered either way — output 6x input, and reasoning bills as output, which is why the `--effort` caps budget for thinking and not just visible text |
| `call_openrouter.sh` | OpenRouter balance |
| `call_ollama.sh` | free |
| `run_headless.sh` | **different meter than interactive** — read the script's warning |

Every metered shim now prints an estimated cost to stderr **before** it sends
anything, and refuses above `FACTORY_COST_THRESHOLD_USD` (default `$1.00`)
unless the call carries `--authorize-cost`. The estimate is a forecast, not a
ceiling: `max_tokens` bounds output, nothing bounds a multi-pass model
re-billing its input, and measured runs came in up to 26% over. It is never
written to `usage.est_cost_usd`, which stays reserved for what a provider
actually reported. Details and the measurements:
[`docs/hardening-2026-08.md`](docs/hardening-2026-08.md) §6.

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
