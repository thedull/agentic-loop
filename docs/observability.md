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

| # | Item | Current handling |
|---|---|---|
| F1 | Do `SubagentStart/Stop` payloads carry the child `transcript_path`? Docs ambiguous | token/model extraction is best-effort `// null`; duration and summary never depend on it |
| F2 | Matcher support on `SubagentStart` is contradictory in docs | no matchers; filtering in-script by `agent_type` |
| F3 | Transcript JSONL internals are version-dependent | tolerant jq (`.message.usage // .usage`), schema carries `v` |
| F6 | Some versions may show a trust prompt for plugin hooks | harmless; approve once |

Verified in synthetic tests (2026-07-15): pairing/duration, both usage
shapes, agent filtering, run-id correlation across hook/shim/headless
sources, off-state zero-write, tracker/gate events, renderer rollups
matching jq-computed sums.

## Complementary tools

- `CLAUDE_CODE_ENABLE_TELEMETRY=1` (native OTel) for org-level dashboards —
  no per-subagent attribution outside the enhanced-telemetry beta.
- `npx ccusage` for post-hoc subscription-spend audits from Claude Code's own
  logs (covers what the hooks see, not the non-Claude shims — the event log
  covers both).
