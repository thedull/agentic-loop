# Observability — reference

Opt-in event log + run-tree reports for the loop and the factory. Design
rationale: `docs/observability-evals-analysis.md` §1–2. This page is the
operating reference.

## Enable / disable

```bash
/agentic-loop:config observability on     # writes .agentic/config.json
/agentic-loop:config observability off
AGENTIC_OBSERVE=1 ./scripts/run_headless.sh …   # one-off override
AGENTIC_OBSERVE=0                                # hard off (wins over config)
```

Off = every capture point is a silent no-op (one file-stat per hook event,
zero writes). On = events append to
`.agentic/observability/events-YYYYMMDD.jsonl`. Everything lives under
`.agentic/` (gitignored); nothing leaves the machine.

## What gets captured

| Source | Instrument | Events |
|---|---|---|
| native subagents | plugin hooks (`hooks/hooks.json` → `scripts/observe.sh`) | `run_start`, `agent_start`, `agent_stop` (duration, summary from the final message, best-effort tokens/model from the transcript), `run_end` |
| bash shims (`call_*.sh`) | envelope tap in `scripts/lib/common.sh` | `shim_call` — exact model, authoritative tokens + `est_cost_usd`, duration, status, summary, the brief's objective |
| headless loops | `scripts/run_headless.sh` | `headless_start` / `headless_iteration` (cost, usage, check result) / `headless_end` (ok/postponed/error/exhausted) |
| factory | `scripts/lib/tracker.sh`, `scripts/lib/usage_gate.sh` | `tracker_transition` (from→to, actor), `gate` (postpone verdicts) |
| orchestrator decisions | `scripts/observe.sh emit …` | `feature_toggle`, `missing_dependency` |

Only `loop-*` subagents are logged by default; set
`.observability.all_agents: true` in the config to capture every subagent.

## Event schema (v1)

One JSON object per line: `v, ts, event, source, run_id, session_id,
agent_id, agent_type, tier, model, usage{input_tokens, output_tokens,
cache_read_input_tokens, cache_creation_input_tokens}, est_cost_usd,
duration_ms, status, exit_code, summary, detail{}`.

Principles: nulls are honest (nothing is fabricated); `est_cost_usd` stays
null for subscription tiers — they are shared capacity, not dollars; the
renderer reports metered $ and subscription tokens separately. `run_id`
ties events together: the root session id (hooks), `hl-<epoch>-<pid>` for
headless loops (exported as `AGENTIC_RUN_ID` so shim calls inside the loop
correlate), `adhoc` for stray shim calls.

## Reports

```bash
/agentic-loop:config render               # or directly:
./scripts/observe_render.sh               # HTML → .agentic/observability/reports/
./scripts/observe_render.sh --tty         # terminal tree
./scripts/observe_render.sh --run <id>    # specific run (default: latest)
./scripts/observe_render.sh --summarize   # fill missing summaries via local
                                          # Ollama; skips silently if not running
```

The HTML report is fully self-contained (no CDN, no network). Shim calls are
attached to the subagent whose start/stop interval contains them — a
time-overlap heuristic, drawn dashed. Honest over pretty.

## Mining the log (the flywheel)

The flat JSONL is built to be mined (`jq` away), and `./evals/mine.sh`
drafts eval cases from failures automatically — see `evals/README.md`.
This is the traces → mine → curate evals → experiment loop the design
follows; `feature_toggle` events make flag experiments measurable
(correlate `minimize` on/off with tokens, revisions, failure rates).

## Known open items (verify on first real run)

| # | Item | Status |
|---|---|---|
| F1 | Does `SubagentStop` carry the child `transcript_path`? | **RESOLVED YES** (2026-07-16, CLI 2.1.207): a real `loop-worker-cheap` spawn produced an `agent_stop` with the child's transcript path, from which the hook extracted model (`claude-haiku-4-5-20251001`) and true token counts. Extraction stays best-effort `// null` for version drift (F3) |
| F2 | Matcher support on `SubagentStart` is contradictory in docs | no matchers; filtering in-script by `agent_type` |
| F3 | Transcript JSONL internals are version-dependent | tolerant jq (`.message.usage // .usage`), schema carries `v` |
| F4 | Plugin-scoped `--agent` names headlessly | **RESOLVED YES**: `claude -p --agent agentic-loop:loop-planner --plugin-dir <repo>` executes the agent. Two required companions (baked into `evals/run_eval.sh`): `--permission-mode acceptEdits` (agents otherwise land in plan mode and write a plan file instead of executing) and `--add-dir` for any input paths outside the cwd |
| F5 | Headless result JSON field shape | **RESOLVED**: carries `total_cost_usd`, `usage` (incl. cache fields + per-iteration breakdown), `session_id`, `num_turns`, `duration_ms`; **no top-level `model` field** in 2.1.207 — our `// null` fallback covers it |
| F6 | Trust prompt for plugin hooks | **RESOLVED for headless**: `--plugin-dir` registered `hooks/hooks.json` and ran `observe.sh` with no blocking prompt |

Verified in synthetic tests (2026-07-15): pairing/duration, both usage
shapes, agent filtering, run-id correlation across hook/shim/headless
sources, off-state zero-write, tracker/gate events, renderer rollups
matching jq-computed sums.

Verified LIVE (2026-07-16, CLI 2.1.207): a real `call_ollama.sh` worker run
produced a valid envelope and a `shim_call` event with authoritative
tokens/duration; the ollama judge tier discriminates (planted-good candidate
scored 4, garbage scored 2); a real subagent spawn was captured end to end
(paired start/stop, 6.6s duration, model + true tokens from the child
transcript) and rendered as a run tree; and the full live eval suite passed
6/6 (planner routing ×2, consolidator missing-artifact, reviewer seeded
SQL-injection, spec-gate ambiguity, red-gate vacuous check) alongside the
15/15 free suite.

Two operational caveats found live: close stdin (`< /dev/null`) when
invoking shims from a non-interactive shell without a piped brief (they
read stdin whenever it isn't a tty), and prefer a non-thinking local model
for Ollama duty — thinking models can spend the whole budget inside
`<think>` and return an empty (correctly `partial`) result.

## Complementary tools

- `CLAUDE_CODE_ENABLE_TELEMETRY=1` (native OTel) for org-level dashboards —
  no per-subagent attribution outside the enhanced-telemetry beta.
- `npx ccusage` for post-hoc subscription-spend audits from Claude Code's own
  logs (covers what the hooks see, not the non-Claude shims — the event log
  covers both).
