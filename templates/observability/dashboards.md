# Dashboard queries — the three boards

**You probably don't need to read this file to get the dashboards** — run
`./scripts/observe_dashboards_import.sh` (see `README.md` step 4) to import
all 14 panels below as three ready-made, verified boards in one command.
This file is the source those boards are generated from (via
`scripts/observe_dashboards_gen.py`) and the reference for customizing a
panel or writing your own query by hand.

One panel per query, over the `agentic` stream (SQL tab in OpenObserve's
panel editor, if you're building by hand). Field names are the event schema
verbatim — see `docs/observability.md`. Every board splits metered $ from
subscription tokens; nothing here blends them.

The leaf-event filter appears in most queries — it is the same
no-double-counting rule the renderer uses:

```sql
event IN ('shim_call', 'agent_stop', 'headless_iteration')
```

## Board 1 — Tonight (the phone board, evening review)

**Today's metered spend ($)** — single stat:
```sql
SELECT SUM(est_cost_usd) AS metered_usd FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
```

**Today's subscription tokens** — single stat (in/out):
```sql
SELECT SUM(usage_input_tokens) AS tok_in, SUM(usage_output_tokens) AS tok_out
FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
  AND est_cost_usd IS NULL
```

**PRs opened** — table:
```sql
SELECT ts, detail_spec_file AS spec FROM agentic
WHERE event = 'tracker_transition' AND detail_to_status = 'pr-open'
ORDER BY ts DESC
```

**LLM-layer errors** — table (API failures, partial/empty output — not
spec-level blocked):
```sql
SELECT ts, agent_type, tier, model, status, summary FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
  AND status IN ('error','partial')
ORDER BY ts DESC
```

**Gate postpones** — table:
```sql
SELECT ts, detail_resets_at FROM agentic WHERE event = 'gate' ORDER BY ts DESC
```

Set the board's time range to "Today"; every panel inherits it.

## Board 2 — The Factory (weekly trends)

**Latency: p50/p90 stage duration by phase** — time series:
```sql
SELECT histogram(ts) AS t, phase,
       approx_percentile_cont(duration_ms, 0.5) AS p50,
       approx_percentile_cont(duration_ms, 0.9) AS p90
FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
  AND duration_ms IS NOT NULL
GROUP BY t, phase ORDER BY t
```

**Traffic: activity by phase** — stacked bars:
```sql
SELECT histogram(ts) AS t, phase, COUNT(*) AS events FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
GROUP BY t, phase ORDER BY t
```

**Errors: LLM-layer error rate** — time series:
```sql
SELECT histogram(ts) AS t,
       SUM(CASE WHEN status IN ('error','partial') THEN 1 ELSE 0 END) * 100.0
         / COUNT(*) AS err_pct
FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
GROUP BY t ORDER BY t
```

**Saturation: gate postpones per day** — bars (the moments the loop hit
the subscription ceiling):
```sql
SELECT histogram(ts) AS t, COUNT(*) AS postpones FROM agentic
WHERE event = 'gate' GROUP BY t ORDER BY t
```

**Spend by phase** — stacked bars:
```sql
SELECT histogram(ts) AS t, phase, SUM(est_cost_usd) AS metered_usd
FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
GROUP BY t, phase ORDER BY t
```

**Deterministic vs stochastic activity** — time series:
```sql
SELECT histogram(ts) AS t,
       SUM(CASE WHEN event IN ('shim_call','agent_start','agent_stop',
                               'headless_iteration') THEN 1 ELSE 0 END) AS stochastic,
       SUM(CASE WHEN event NOT IN ('shim_call','agent_start','agent_stop',
                                   'headless_iteration','run_start','run_end')
                THEN 1 ELSE 0 END) AS deterministic
FROM agentic GROUP BY t ORDER BY t
```

## Board 3 — Spec Economics (the estimation board)

**Tokens per spec** — bars:
```sql
SELECT spec_id, SUM(usage_input_tokens + usage_output_tokens) AS tokens
FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
  AND spec_id IS NOT NULL
GROUP BY spec_id ORDER BY tokens DESC
```

**Errors per spec** — bars:
```sql
SELECT spec_id,
       SUM(CASE WHEN status IN ('error','partial') THEN 1 ELSE 0 END) AS llm_errors
FROM agentic
WHERE event IN ('shim_call','agent_stop','headless_iteration')
  AND spec_id IS NOT NULL
GROUP BY spec_id ORDER BY llm_errors DESC
```

**Re-open leaderboard** — table (claims into building beyond the first):
```sql
SELECT detail_spec_file AS spec, COUNT(*) - 1 AS reopens FROM agentic
WHERE event = 'tracker_transition' AND detail_to_status = 'building'
GROUP BY detail_spec_file HAVING COUNT(*) > 1 ORDER BY reopens DESC
```

The estimation table itself (p25/p50/p75 per effort_budget with the N
guard) joins spec-file facts the store does not have — read it from
`./scripts/observe_metrics.sh estimate`, which is its source of truth.

> Column-name note: OpenObserve flattens nested JSON with underscores
> (`usage.input_tokens` → `usage_input_tokens`, `detail.to_status` →
> `detail_to_status`). If your instance is configured differently, adjust
> the names once here — the event schema itself never moves.

## Comprehension proxies

```
scripts/observe_metrics.sh comprehension [--since D] [--until D] [--format tsv]
```

Four numbers that **correlate** with comprehension debt. None of them measures
it, and the rendering says so on every run.

| column | meaning |
|---|---|
| `diff_added` / `diff_removed` | size of the **final** build cycle's diff, from spec 013 |
| `findings` | the blind review's finding count for that final cycle |
| `findings_per_100_changed` | findings ÷ (added + removed) × 100. **null** when the denominator is 0 — a review of a zero-line diff has no density |
| `merge_latency_ms` | the existing `pr-open → done` segment, reused rather than recomputed |
| `build_churn` | transitions back into `building` **before** merge |

Two things this deliberately does not do.

**`build_churn` is not a post-merge signal.** It counts re-entry into `building`
before the PR opens. `done` is terminal in the tracker, so no post-merge signal
exists to report — and manufacturing one from a pre-merge counter would be the
fabrication the honest-nulls rule forbids.

**Multi-cycle specs report their last cycle, not a sum.** Summing would
double-count code that was rewritten rather than added. `build_churn` is shown
alongside so a one-cycle and a five-cycle spec are never read as comparable.
