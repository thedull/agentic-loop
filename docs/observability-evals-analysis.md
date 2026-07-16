# Observability, evals, and cost optimization — analysis & design

Research companion for three planned additions to the agentic-loop plugin. Analysis
only — nothing in this document is implemented yet. Facts about Claude Code behavior
were verified against code.claude.com docs on 2026-07-15; anything that could NOT be
verified is flagged inline as **F1–F6** and collected in the appendix.

Covers both configurations:

- **Base loop** (`main`): tier-routed orchestration, native subagents, bash shims.
- **Factory** (`claude/agentic-loop-analysis-ar17ts`): the unattended
  spec→build→review pipeline layered on top (see `docs/factory.md` on that branch).

Motivating sources:

- [Improving agents is a data mining problem](https://www.langchain.com/blog/improving-agents-is-a-data-mining-problem)
  (LangChain) — traces are the substrate; the flywheel is *mine traces → curate
  evals → run experiments*.
- [LLM evaluation frameworks compared](https://machinelearningmastery.com/llm-evaluation-frameworks-compared-how-to-actually-measure-what-your-model-does/)
  (MachineLearningMastery) — RAGAS vs DeepEval vs Promptfoo; LLM-as-judge bias
  catalog (position, self-preference, verbosity).

---

## 1. Verdicts up front

**Ready-made observability library? No — build on native mechanisms.**
LangSmith/Langfuse instrument SDK callables (Python/JS). This repo's units of work
are native Claude Code subagents and curl-based bash shims — there is nothing for
those SDKs to wrap; you would write custom ingestion anyway, plus adopt a
Python/Node runtime this repo deliberately avoids, plus (LangSmith) ship transcripts
off-machine or (Langfuse) run Docker infra. Meanwhile Claude Code natively provides
everything needed: `SubagentStart`/`SubagentStop` hooks carrying `agent_id`/
`agent_type`, per-subagent JSONL transcripts with per-message `model` and token
`usage`, headless `total_cost_usd`, and plugin-shipped hooks via `hooks/hooks.json`.
A flat local JSONL event log is also exactly the mining substrate the LangChain
flywheel wants — you can `jq` it. The event schema below is deliberately span-shaped
(paired start/stop, ids, parent refs), so a later OTLP exporter could ship it to any
backend without re-instrumenting. Claude Code's own OTel
(`CLAUDE_CODE_ENABLE_TELEMETRY=1`) is complementary for org dashboards, but has no
per-agent attribution outside a beta, and OTEL_* vars are stripped from hook
subprocesses — it cannot replace the local log.

**Ollama summarization of each operation? Viable, but ~90% redundant.**
Most nodes already carry a human-written summary for free: shim envelopes have a
contractual `summary` (≤100 words, enforced by `scripts/lib/validate_envelope.jq`),
and `SubagentStop` delivers the subagent's `last_assistant_message`. Ollama
(`scripts/call_ollama.sh` already exists, cost $0) earns exactly one place: an
optional `--summarize` flag on the report renderer, applied only to summary-less or
overlong nodes (e.g. raw headless iterations). Never at capture time — a hook
blocking on Ollama adds latency to every subagent stop and breaks when Ollama isn't
running. Never a paid tier for telemetry.

**Evals for the plugin? Applicable and worthwhile — but bespoke, not a framework.**
The things under test are (a) subagent *prompt files* that only execute inside
Claude Code, (b) bash shims whose contract is envelope validity, (c) bash state
machines (factory `tracker.sh`). Promptfoo's native providers can't run any of
these (you'd wrap everything in its `exec` provider — i.e. write the bash anyway,
plus adopt npm and a YAML assert DSL that can't express "verify `artifacts[]` paths
exist on disk"). DeepEval is pytest (no Python here); RAGAS is RAG-only (no RAG
here). The repo already owns the hard parts: `validate_envelope.jq` (schema oracle),
the shims (judge transport, including **cross-family** judges), and the 6-field
brief (case format). A small bash runner completes it. Escape hatch: if a results
web UI is ever wanted, promptfoo's `exec` provider can wrap the runner later
without rework.

---

## 2. Observability design

### 2.1 Opt-in and activation

Plugins can ship hooks that activate automatically when the plugin is enabled
(`hooks/hooks.json` at plugin root, `${CLAUDE_PLUGIN_ROOT}` substitution — verified
against the plugins docs). So unlike `templates/hooks-spawn-guard.json` (which the
user hand-merges into settings), observability hooks ship plugin-level and the
**opt-in gate lives inside the hook script**:

```bash
# first lines of observe.sh
CFG="${CLAUDE_PROJECT_DIR:-.}/.agentic/observability/config.json"
[[ -f "$CFG" || "${AGENTIC_OBSERVE:-}" == "1" ]] || exit 0   # silent no-op, ~1ms
```

Toggled by a skill (see §5 for the generalized `/agentic-loop:config`); the
`AGENTIC_OBSERVE=1` env override serves one-off headless runs. Users who never opt
in pay one file-stat per hook event and get zero files written. Everything lands in
`.agentic/`, which is already gitignored.

### 2.2 Capture points (four)

| Source | Where | What it emits |
|---|---|---|
| `hook` | new `scripts/observe.sh` wired via new `hooks/hooks.json` (SessionStart, SubagentStart, SubagentStop, Stop, SessionEnd) | `run_start`, `agent_start`, `agent_stop`, `run_end`. Duration from a `state/agent-<agent_id>.start` marker pair (constant-time, no log scans). Summary from `last_assistant_message` (truncated). Tokens/model best-effort from the subagent transcript **(F1, F3)**. Filter `agent_type` matching `(^|:)loop-` in-script, not via matchers **(F2)**. Every path exits 0 — hooks must never break the loop. |
| `shim` | `scripts/lib/common.sh` — `finalize_envelope()` (line ~194) and `emit_error()` (line ~61) | `shim_call` with worker, exact model, authoritative usage + `est_cost_usd` (the envelope already carries all of it), duration (timer set when the script sources common.sh), status, summary, and `detail.objective` — the future eval-case seed. stdout stays contractually reserved for the envelope; the event append goes only to the log file. |
| `headless` | `scripts/run_headless.sh` | `headless_start` / `headless_iteration` (session_id, usage, `total_cost_usd`, `check_cmd_passed`) / `headless_end` on every exit path — including the factory branch's exit-7 usage-cap postpone (`status: "postponed"`). |
| `tracker` (factory branch) | `scripts/lib/tracker.sh` `tracker_advance`/`tracker_claim`; `scripts/lib/usage_gate.sh` | `tracker_transition` with `{spec_file, from_status, to_status, actor}`; a `gate` event on postpone verdicts. |

### 2.3 Event log — one unified JSONL

```
.agentic/observability/
  config.json               # opt-in marker + settings
  events-YYYYMMDD.jsonl     # ONE append-only log, all sources
  state/                    # per-agent start markers + current run_id
  reports/                  # rendered HTML
```

Single dated file, not per-run directories: multiple concurrent writers (hook, shim,
headless, tracker) append without resolving a run dir; the mining flywheel wants a
flat corpus; `run_id` is a field and the renderer filters by it. Single-line
`O_APPEND` writes are atomic at these line sizes — same pragmatism as the factory's
mkdir locks.

Event schema v1 (one object per line):

```json
{
  "v": 1,
  "ts": "2026-07-15T21:14:03.512Z",
  "event": "run_start|run_end|agent_start|agent_stop|shim_call|headless_start|headless_iteration|headless_end|tracker_transition|gate|feature_toggle|missing_dependency",
  "source": "hook|shim|headless|tracker",
  "run_id": "sess-abc123",
  "session_id": "sess-abc123",
  "agent_id": "subagent-uuid-or-null",
  "agent_type": "agentic-loop:loop-worker-cheap | fable | ollama/qwen3.5:4b | ...",
  "tier": "ollama|haiku|sonnet|fable|sol|openrouter|headless|null",
  "model": "claude-haiku-4-5 | null",
  "usage": {"input_tokens": 0, "output_tokens": 0,
            "cache_read_input_tokens": null, "cache_creation_input_tokens": null},
  "est_cost_usd": 0.0,
  "duration_ms": 12345,
  "status": "ok|partial|error|blocked|needs_escalation|needs_input|postponed|null",
  "exit_code": 0,
  "summary": "<=100 words, from envelope.summary or last_assistant_message",
  "detail": { }
}
```

Principles: **nulls are honest** — never fabricate tokens the source didn't report.
`est_cost_usd` is `null` for subscription tiers (they're shared capacity, not
dollars; the renderer shows tokens for them and dollars for metered tiers only).
Shims report exact model + computed cost; native subagents get model from the
transcript when available, else mapped from the agent frontmatter.

### 2.4 Hierarchy reconstruction

The tree is `run_id → session_id → agent_id`, built from paired
`agent_start`/`agent_stop` events (subagent hooks fire in the parent session, so
`session_id` on those events IS the parent). Native subagents can't spawn subagents,
so hook depth is bounded. Shim calls carry no agent identity: the renderer attaches
each `shim_call` to the agent whose `[start, stop]` interval contains it
(time-overlap heuristic), else to the session root — and marks heuristic
attachments visually. Honest over pretty.

### 2.5 Renderer

`scripts/observe_render.sh` — bash + jq (no new runtime; the repo's only preflight
deps stay jq/curl/claude):

- `--run <id>` (default latest), `--out <file>`, `--tty`, `--summarize`.
- **HTML mode**: jq groups/pairs/rolls up into one JSON blob → heredoc HTML with
  embedded `const EVENTS = …` + ~150 lines of vanilla JS. Collapsible tree,
  per-node badges (model, tokens in/out, est $, duration, status color), root
  rollups (total tokens, metered $ separated from subscription tokens, wall time,
  per-tier bar). Self-contained file, no CDN, no network.
- **`--tty` mode**: pure jq/awk indented tree for mid-run checks:

  ```
  run sess-abc123 · 14m32s · 96.4k tok · $0.14 metered
  ├─ loop-planner        [sonnet]  4.1k→1.2k tok ·  38s · ok  — "split into 3 subtasks"
  ├─ loop-worker-cheap   [haiku]   3.2k→0.8k tok ·  41s · ok  — "extracted 14 TODOs"
  ├─ ollama/qwen3.5:4b   [ollama]  2.0k→0.3k tok ·  12s · ok  — "classified 30 items"   (shim·heuristic)
  ├─ loop-consolidator   [sonnet]  9.8k→1.9k tok ·  74s · ok  — "merged; 1 disagreement"
  └─ loop-reviewer       [sonnet]  8.4k→1.1k tok ·  66s · partial — "2 findings, 1 blocking"
  ```

- **`--summarize`**: nodes with null/overlong summaries piped through
  `./scripts/call_ollama.sh` ("summarize in ≤25 words…"); skipped silently if
  Ollama isn't running. Free, local, render-time only.

---

## 3. Evals design

### 3.1 Layout

```
evals/
  README.md                  # protocol, cost table, how to add cases
  run_eval.sh                # discovers cases, executes, checks, writes results
  judge.sh                   # LLM-judge wrapper over the existing shims
  mine.sh                    # flywheel: observability JSONL -> draft cases
  rubrics/                   # anchored 1-4 ordinal rubrics
  cases/
    envelope/                # tier 0: pure-bash fixtures for common.sh   ($0)
    planner-routing/         # tier 1: headless planner runs
    consolidator/            # tier 1 + judge
    reviewer/                # tier 1 + judge, seeded defects
    tracker/                 # (factory) pure-bash state machine          ($0)
    usage-gate/              # (factory) fixture usage.json files         ($0)
    spec-gate/               # (factory) planted-ambiguity specs
    red-gate/                # (factory) vacuous check_cmd must block
    _inbox/                  # mined drafts awaiting human curation
  fixtures/                  # tiny repos/artifacts cases point at
  results/                   # gitignored: results-<ts>.jsonl + summary
```

### 3.2 Case format — the 6-field brief IS the input format

```json
{
  "id": "planner-003-mechanical-bulk",
  "target": "loop-planner",
  "kind": "headless-agent | bash-unit | shim",
  "input": { "brief": { "objective": "…", "user_intent_verbatim": "…",
             "input_paths": [], "boundaries_non_goals": [], "output_spec": "…",
             "effort_budget": "…" } },
  "checks": [
    { "type": "envelope_valid" },
    { "type": "jq", "expr": ".result.subtasks | length <= 3" },
    { "type": "tier_expect", "map": { "t1": ["ollama","haiku"], "t2": ["sonnet"] } },
    { "type": "artifact_exists", "paths_from": ".artifacts" },
    { "type": "judge", "rubric": "rubrics/reviewer-findings.md",
      "must_find": ["sql-injection in fixtures/app.py:42"], "min_score": 3 }
  ],
  "provenance": { "source": "hand|mined", "run_id": null, "date": "2026-07-15" }
}
```

Check types are a fixed, small set implemented once in `run_eval.sh`:
`envelope_valid` (pipe through `validate_envelope.jq` — free regression of the
schema contract), `jq` (arbitrary boolean), `tier_expect` (routing assertion),
`artifact_exists`, `exit_code`, `judge`.

### 3.3 Execution kinds

- **bash-unit** ($0, deterministic, seconds): source `common.sh` /
  `tracker.sh` / `usage_gate.sh` in a temp sandbox, feed fixtures through
  `extract_json_object` / `finalize_envelope` / `tracker_advance`, assert. Home of
  envelope-schema regression, tracker state-machine, and gate-threshold cases.
  Run via `evals/run_eval.sh --free`.
- **headless-agent**: `claude -p --agent agentic-loop:loop-planner
  --output-format json` with the brief as prompt, in a throwaway fixture dir
  **(F4 — needs a 5-minute spike; fallback `--append-system-prompt`)**. Same
  billing caveats as `run_headless.sh`; suites stay ≤10 cases per target and run
  manually, never on a timer.
- **shim**: `call_ollama.sh` live when Ollama is present ($0); metered shims tested
  against canned responses via a 3-line `MOCK_RESPONSE_FILE` seam (skip curl when
  set) — $0, still exercises ~95% of the shim code path.

### 3.4 Judge protocol — tiered, cross-family, bias-hardened

1. **Deterministic first, judge last.** Planted-defect detection is grep/jq
   (`must_find`), never a judge. Judges only grade free-form quality (finding
   usefulness, consolidation fidelity, spec clarity).
2. **Judge tier ladder:** `call_ollama.sh` (free) for mechanical rubric checks
   ("does the finding list mention X? yes/no"); `call_openrouter.sh --model kimi`
   (pennies, **cross-family** — dodges same-family self-preference bias) as the
   default quality judge for Claude-produced outputs; `call_sol.sh` never in evals
   by default (a `--judge sol` flag exists behind the same explicit-confirmation
   ethos as escalation).
3. **Bias mitigations baked into `judge.sh`** (from the framework-comparison
   article): judge never sees which agent/model produced the candidate (blind
   provenance); A/B regression comparisons run both orderings and count only
   agreements (position bias); candidates truncated to a fixed cap + rubric says
   "do not reward length" (verbosity bias); anchored 1–4 ordinal scales with
   per-level exemplars, never free-form scores; judge output is itself an
   envelope, schema-validated.
4. **Cost expectations:** free suites $0; planner-routing ~8 headless sonnet calls;
   judged suites ~10 headless + ~10 OpenRouter judge calls ≈ $0.05–0.20 metered;
   the entire suite well under $0.50 per full run.

### 3.5 The flywheel — `mine.sh`

`mine.sh --since 7d` scans `.agentic/observability/events-*.jsonl` for
`status ∈ {error, blocked, partial, needs_escalation}`, shim calls with caveats,
tracker `blocked` transitions, and headless runs that exhausted iterations. Each hit
becomes a draft case in `evals/cases/_inbox/` pre-filled with the captured
`objective`, run_id provenance, and a TODO checks stub. **Mining proposes, humans
curate** — nothing auto-commits. This is why `detail.objective` is captured on shim
events: today's failure is tomorrow's regression case, exactly the LangChain loop.

---

## 4. Cost optimization — community plugin adoption matrix

Twelve tools assessed (GitHub stars/dates verified 2026-07-15/16). Honest maturity
flag: the "automatic model routing" category has **no** community-established
project — every candidate is a 3–53★ solo repo with unverified claims.

| Tool | Stars | Mechanism | Verdict |
|---|---|---|---|
| [ponytail](https://github.com/DietrichGebert/ponytail) | 84k | Skills + hooks: code-minimization decision ladder (YAGNI→reuse→stdlib→native→existing dep→one-liner→minimum) | **Adopt** — inject ladder rules into build-stage worker briefs |
| [grill-with-docs](https://github.com/mattpocock/skills) | 172k (repo) | Pure interaction-pattern skill (Matt Pocock's `mattpocock/skills`): relentless pre-plan interview that also drops ADRs + a glossary as it goes | **Adopted** — deep-mode provider for the `grill` flag (`grill deep on`): runs on `large`/domain-heavy ideas when installed; native grilling with the cap lifted otherwise |
| [guard-skills](https://github.com/amElnagdy/guard-skills) | 1.0k | Zero-dep skill files: clean-code-guard, test-guard | **Adopt** — fold criteria into reviewer checklist |
| [cache-audit](https://github.com/ussumant/cache-audit) | 57 | Read-only skill scoring setup against Anthropic's caching rules | **Adopt, one-time** — quantify tier-hopping cache-miss cost |
| [ccusage](https://github.com/ccusage/ccusage) | 17k | CLI reading local usage JSONL; cost reports | **Adopt-with-config** — optional npx companion, not wired into core |
| [cozempic](https://github.com/Ruya-AI/cozempic) | 352 | Hooks + Python daemon: tiered context pruning | **Adopt-with-config** — cautious pilot, interactive sessions only; test against spawn-guard |
| [caveman](https://github.com/juliusbrussee/caveman) | 90k | Skill + hooks: terse-output compression (~65% output reduction claimed) | **Test-before-adopt** — tension with envelope contract (below) |
| [Claude-Code-Usage-Monitor](https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor) | 8.5k | Python TUI, live burn-rate vs caps | Skip — weaker-fit alternative to ccusage (heavy Python deps) |
| [Superpowers](https://github.com/obra/superpowers) | 255k | Full skills framework: brainstorm→plan→TDD→review | Skip framework — redundant with hub-and-spoke + factory; cherry-pick skill files as prompt material |
| [magic-compact](https://github.com/aerovato/magic-compact) | 113 | Replaces tool I/O with retrievable omission notices | Too immature; pattern already realized by envelope artifact+digest design |
| [prompt-caching](https://github.com/flightlesstux/prompt-caching) | 130 | Auto cache_control injection | Unverified vs built-in caching; skip |
| model-routing hooks (3 repos) | 3–53 | Regex/keyword prompt classifiers → model choice | **Conflicts** — do not adopt (below) |

**Where the two user-named plugins fit:**

- **ponytail** belongs in the **build-stage worker briefs**: its decision ladder
  makes cheap-tier workers default to the smallest sufficient diff *at generation
  time*. Its own agentic benchmark: 54% fewer LOC, 22% fewer tokens, 20% cheaper,
  27% faster with safety checks untouched — cost falls out of building less, which
  is the "building the right things" half of the ask. Its lifecycle hooks need
  Node, but the rules content is copyable into brief text, so the dependency is
  avoidable. Complementary to guard-skills (prevent-at-generation vs
  catch-at-review).
- **caveman** is in **tension with, not synergy with**, the envelope contract —
  `envelope_instructions()` in `scripts/lib/common.sh` already mandates "Be terse:
  output tokens are expensive", and the artifact+digest rule already compresses at
  the content layer. If caveman's compression degrades structured-JSON fidelity it
  breaks `validate_envelope.jq` — a direct conflict. Needs a concrete compatibility
  test before adoption. Legitimate niches: orchestrator-turn narration (outside
  envelopes) and `/caveman-compress` on `LEARNINGS.md` (~46% permanent input-token
  cut claimed). Note its ~1–1.5k input-token/turn overhead — net savings depend on
  session shape.

**Why the model-routing hooks are rejected outright:** they do implicitly (regex
complexity guesses on raw prompts) what `loop-planner` does explicitly and
auditably (per-subtask tier assignment in the 6-field brief). Layering them on
would let a keyword classifier silently fight the planner over which model runs —
a strict downgrade in a system whose core discipline is explicit routing.

**Unverified claims flagged:** gearbox's "10/10 routing accuracy" and cozempic's
savings percentages are single-author self-reports with no independent benchmarks;
treat as marketing until tested locally.

---

## 5. Unified feature flags — opt-in everything, log every judgment

All of the above ships behind explicit, **default-off** flags in one place:
`.agentic/config.json`, one entry per feature, one documentation table, no
scattered env vars:

```json
{
  "observability": { "enabled": true },
  "minimize":      { "enabled": false, "agent_judgment": true },
  "grill":         { "enabled": false, "agent_judgment": true },
  "guards":        { "enabled": true  },
  "summarize":     { "enabled": false }
}
```

- `minimize` = ponytail ladder in build-worker briefs; `grill` = pre-planning
  interview (native; a later `deep` sub-flag escalates `large`/domain-heavy
  ideas to grill-with-docs when installed, native-uncapped otherwise);
  `guards` = guard-skills criteria in the reviewer checklist;
  `summarize` = the Ollama render fallback.
- **Precedence:** per-run skill flag > user config default > agent judgment.
  The agent may toggle a feature per-task **only** where the user set
  `agent_judgment: true`, and every judgment toggle emits a `feature_toggle`
  event (`{feature, scope, reason, decided_by}`) to the observability log. That
  makes flag efficacy mineable and A/B-evaluable — flags are the *experiment*
  layer of the flywheel: correlate `minimize` on/off with tokens, revision
  counts, and failure rates, then turn the answer into eval suites.
- **Unattended constraint:** factory stages may never judgment-enable anything
  metered — mirrors the existing no-metered-escalation-unattended rule.
- **Third-party dependencies — consent-to-install, no extra flags.** Enabling a
  feature checks its dependency at that moment: if ponytail is missing when the
  user runs `/agentic-loop:config minimize on`, the orchestrator shows the install
  command and asks install-now / enable-anyway / cancel. Interactively at run
  time, ask once and persist a decline as `install_declined: true` in that
  feature's entry (no re-nagging; this field subsumes any `--only-installed-skills`
  flag). Unattended stages never ask and never install — they emit a
  `missing_dependency` event and continue without the feature, so the gap shows up
  in the evening digest instead of silently no-opping. `doctor.sh` reports
  dependency presence either way.
- The observability toggle skill generalizes to
  `/agentic-loop:config <feature> on|off|status` (plus `render` for reports).

---

## 6. What lands where, in what order

**On main (base loop):**

1. *Capture core* — `scripts/lib/obs.sh`, `scripts/observe.sh`, `hooks/hooks.json`,
   config skill, `doctor.sh` check, instrumentation in `common.sh` +
   `run_headless.sh`.
   Verify: with observability OFF, run a `loop-worker-cheap` task → assert zero
   writes; ON, run the same + one `call_ollama.sh` + a 1-iteration headless run →
   assert paired agent events with duration, a `shim_call` with usage, headless
   events. Resolve **F1** empirically and record the answer here.
2. *Renderer* — `observe_render.sh` (tty → HTML → `--summarize`).
   Verify: rollup totals equal jq-computed sums; kill Ollama, confirm
   `--summarize` degrades silently.
3. *Evals core* — **F4** spike → runner + free envelope suite → headless suites
   (planner-routing, consolidator artifact-verification, reviewer seeded-defects)
   → `judge.sh` + rubrics → `mine.sh`.
   Verify: `--free` green at $0; full run produces a baseline; deliberately break
   `validate_envelope.jq` locally and confirm the suite catches it; run one judged
   case twice with swapped A/B order and confirm order-invariance handling.
4. *Flags & plugin adoption* — `.agentic/config.json` schema, consent-to-install
   flow, ponytail rules into worker briefs, guard criteria into
   `agents/reviewer.md`, grill-with-docs as optional pre-planning step, caveman
   compatibility test against the envelope schema, one-time cache-audit run.

**On the factory branch (after it takes main in):**

5. *Factory instrumentation* — `tracker.sh` transition events, `usage_gate.sh`
   gate events, exit-7 postpone event in its `run_headless.sh`, digest lines in
   `.agentic/STATUS.md` gain `run: <run_id>`.
6. *Factory eval suites* — tracker state-machine ($0), usage-gate fixtures ($0),
   spec-gate planted-ambiguity, red-gate vacuous-check (integration, manual).
   Verify: drive one spec through spec→build→review with observability on; render
   the tree — tracker transitions appear under the run.

**Docs/polish (main):** this doc graduates into `docs/observability.md` +
`evals/README.md` reference material; README + `templates/CLAUDE.md` pointers;
plugin.json version bump.

---

## 7. Appendix — open facts the design defends against

| # | Unverified fact | Defense |
|---|---|---|
| F1 | Whether `SubagentStart`/`SubagentStop` stdin includes the **child's** `transcript_path` (docs' common-fields table says yes; per-event examples omit it) | Token/model extraction is best-effort (`// null`); hook never fails; resolve empirically in phase 1 |
| F2 | Docs self-contradict on whether `SubagentStart` honors matchers | Don't use matchers; filter by `agent_type` in-script |
| F3 | Transcript JSONL internal format is version-dependent, not a stable API | All jq uses `// null` fallbacks; events carry `v` so the renderer can adapt |
| F4 | `claude -p --agent agentic-loop:loop-planner` (plugin-scoped name) working headlessly | 5-minute spike first; fallback `--append-system-prompt "$(cat agent body)"` |
| F5 | Headless JSON result carrying `model` + full `usage` breakdown | Taken from docs research, not exercised; phase-1 verification covers it |
| F6 | Whether some Claude Code versions prompt for trust before running plugin hooks | Harmless either way; affects docs UX text only |

Implementation nit: stock macOS bash 3.2 lacks `$EPOCHREALTIME`/GNU `date +%s%N` —
shim duration falls back to second precision (or a `perl -MTime::HiRes` one-liner)
rather than adding a dependency.
