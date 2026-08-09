# Observability — reference

Opt-in event log + run-tree reports for the loop and the factory. Design
rationale: `docs/observability-evals-analysis.md` §1–2. This page is the
operating reference. Architecture, metric catalog, platform comparison and
the forward roadmap: [`observability-architecture.md`](observability-architecture.md).

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
| stage context | `scripts/observe.sh context set/clear` (called by the spec/build/review skills at claim + every stop) | `phase_start` / `phase_end` (with the stage duration) — and every event in between carries `phase`/`spec_id` |
| review benches (opt-in) | `scripts/lib/bench.sh` | `bench` — `detail.action` one of `created`, `refreshed`, `conflict`, `error`, `kept_dirty`, `removed`; `detail.slug`/`detail.path`/`detail.branch` as applicable |
| orchestrator decisions | `scripts/observe.sh emit …` | `feature_toggle`, `missing_dependency` |

Only `loop-*` subagents are logged by default; set
`.observability.all_agents: true` in the config to capture every subagent.

## Event schema (v1)

One JSON object per line: `v, ts, event, source, run_id, phase, spec_id,
session_id, agent_id, agent_type, tier, model, usage{input_tokens,
output_tokens, cache_read_input_tokens, cache_creation_input_tokens},
est_cost_usd, duration_ms, status, exit_code, summary, detail{}`.

`phase` (`spec|scout|build|review`) and `spec_id` (the spec file path) are
the correlation keys: defaulted from a run-scoped context file written by
`observe.sh context set` and removed by `context clear` (env
`AGENTIC_PHASE`/`AGENTIC_SPEC_ID` override; a context older than ~30 min is
treated as absent — fail closed). Events from before these keys existed
read null; still v1.

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

## Metrics, retention, export

```bash
./scripts/observe_metrics.sh cost|phase|spec|estimate|mix   # rollups, pure jq
                              # (--since/--until, --format tsv; see --help text)
./scripts/observe_prune.sh    # gzip events >30d, cap reports/ — manual, lossless
                              # (all readers handle .jsonl.gz transparently)
./scripts/observe_push.sh     # cursor-based export to a local OpenObserve —
                              # gated by `observability stack` + O2_URL/O2_AUTH
```

`observe_metrics.sh` is the derive plane: per-phase spend, per-spec tokens/
errors/reopens, two-segment cycle time (`specd→pr-open` machine,
`pr-open→done` merge), the effort_budget estimation table (explicit N,
`sufficient: false` under 5), and the deterministic/stochastic mix. The
export stack (dashboards on your phone via Tailscale) is opt-in:
`templates/observability/README.md` is the recipe. Architecture, metric
catalog and the platform comparison: [`observability-architecture.md`](observability-architecture.md).

## Mining the log (the flywheel)

The flat JSONL is built to be mined (`jq` away), and `./evals/mine.sh`
drafts eval cases from failures automatically — see `evals/README.md`.
This is the traces → mine → curate evals → experiment loop the design
follows; `feature_toggle` events make flag experiments measurable
(correlate `minimize` on/off with tokens, revisions, failure rates).

## Known open items (verify on first real run)

| # | Item | Status |
|---|---|---|
| F1 | Does `SubagentStop` carry the child `transcript_path`? | **REOPENED, then RESOLVED DIFFERENTLY** (2026-07-31). The 2026-07-16 verification saw a genuine child transcript, but production data disagrees: 136 `agent_stop` events in one project all carried the **parent session's** transcript (one 8473-line file whose `sessionId` equalled the event's own `session_id`), so each subagent was credited with the whole session's usage — the origin of a single event claiming 2.28M output tokens. The hook now compares the transcript's `sessionId` to the event's `session_id`: on a match it attributes **nothing** (`usage`/`model` null, `detail.usage_source: "parent-transcript-not-attributable"`); on a genuine child transcript it extracts as before (`usage_source: "subagent-transcript"`). Per-subagent token attribution is therefore unavailable whenever the CLI hands over the parent transcript — by design, rather than fabricated. Eval `observability-020` gates both arms |
| F2 | Matcher support on `SubagentStart` is contradictory in docs | no matchers; filtering in-script by `agent_type` |
| F3 | Transcript JSONL internals are version-dependent | tolerant jq (`.message.usage // .usage`), schema carries `v` |
| F4 | Plugin-scoped `--agent` names headlessly | **RESOLVED YES**: `claude -p --agent agentic-loop:loop-planner --plugin-dir <repo>` executes the agent. Two required companions (baked into `evals/run_eval.sh`): `--permission-mode acceptEdits` (agents otherwise land in plan mode and write a plan file instead of executing) and `--add-dir` for any input paths outside the cwd |
| F5 | Headless result JSON field shape | **RESOLVED**: carries `total_cost_usd`, `usage` (incl. cache fields + per-iteration breakdown), `session_id`, `num_turns`, `duration_ms`; **no top-level `model` field** in 2.1.207 — our `// null` fallback covers it |
| F6 | Trust prompt for plugin hooks | **RESOLVED for headless**: `--plugin-dir` registered `hooks/hooks.json` and ran `observe.sh` with no blocking prompt |
| F8 | Exported events indexed at ingest time, not event time | **RESOLVED** (2026-07-31): OpenObserve falls back to ingest time when a record carries no `_timestamp`, so the first real backfill collapsed 582 events spanning five days onto the single instant of the push — every dashboard time filter was answering "when did I upload this?". `observe_push.sh` now derives `_timestamp` (epoch µs) from each event's own `ts`. This matters most for the offline-batch case the cursor exists to serve, where uploading late is normal. Eval `observability-021` gates it |
| F7 | Per-line usage summing over transcripts over-counts | **RESOLVED** (2026-07-31, found on the first real dashboard read): one API response spans several transcript lines (one per content block / tool_use), each repeating the SAME usage object — naive summing measured 2.6x inflated on a real transcript, and a single `agent_stop` claimed 2.28M output tokens. Extraction now sums once per `message.id` (`max_by` output_tokens per id; id-less older shapes kept as-is). Eval `observability-018` gates it. **`agent_stop` usage captured before v0.14.3 is inflated and should not be trusted for token accounting** — `shim_call`/`headless_iteration` usage was always authoritative (API-reported) and is unaffected |

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

## `diff_size` (spec 013)

Emitted explicitly by the review stage — no hook fires at the moment a diff
exists, so `scripts/observe.sh diff-size --base <ref> --head <ref>` is called
directly. Carries `detail.lines_added` and `detail.lines_removed` against the
branch point.

Both are **null**, never 0, when the answer is unknown: an unresolvable ref, an
empty diff, or a diff whose every row is binary (`git diff --numstat` prints
`-` for those, and counting them as 0 would report "no diff" for a real one).
`0` means a diff that genuinely changed no lines. Spec 011's comprehension
proxies rest on that distinction.
