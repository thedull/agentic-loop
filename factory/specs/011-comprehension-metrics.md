---
id: 011
title: Measure comprehension debt from the existing event log
status: queued
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 011 — Measure comprehension debt from the existing event log

## Brief (the delegation contract)

- **objective**: add a comprehension metric family to `observe_metrics.sh`, derived entirely from data the event log already captures.
- **user_intent_verbatim**: backlog item 7 of `docs/osmani-audit.md` §2.7, closing finding §1.3(c) — the observability plane measures cost, latency, errors, tokens and cycle time, and measures nothing about how much of what ships anyone still understands.
- **input_paths**: `scripts/lib/obs_metrics.jq`, `scripts/observe_metrics.sh`, `templates/observability/dashboards.md`, `evals/cases/comprehension/`
- **boundaries_non_goals**:
  - Does NOT add event types or change the envelope. Every proxy comes from data already captured; if a proxy needs new capture, it is out of scope for this spec.
  - Does NOT claim to measure comprehension. These are proxies, and the output must say so — a number labelled "comprehension" would be a fabrication of exactly the kind `lib/obs.sh` refuses.
  - Does NOT add alerting or thresholds. Reporting only.
  - Does NOT regenerate dashboards by hand; the generator derives them from `dashboards.md` as today.
- **output_spec**: a `comprehension` mode reporting diff size per spec, review-finding density, human merge latency, and re-open rate, each with an explicit null when its source data is absent.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. The mode SHALL report four proxies, each derived only from existing captured data.
   - Given an event log with merged specs, when `comprehension` runs, then it reports diff size per spec, review findings per unit of diff, the `pr-open → done` segment, and re-open count per spec.
2. Missing data SHALL produce null, never a computed-from-nothing value.
   - Given a spec with no `pr-open` transition recorded, when the mode runs, then its merge latency is null and is rendered as null — following the existing honest-nulls rule.
3. The output SHALL label the numbers as proxies.
   - Given any rendering of these metrics, when it is read, then it names them as proxies for comprehension debt rather than as a measurement of it.
4. The mode SHALL accept the same window and format flags as the existing modes.
   - Given `--since`, `--until`, and `--format tsv`, when the mode runs, then it behaves consistently with `cost`, `phase`, `spec` and `mix`.
5. Merge latency SHALL reuse the existing cycle-time segment rather than recomputing it.
   - Given the two-segment cycle time already implemented, when merge latency is reported, then it is the same `pr-open → done` segment, not a second and potentially divergent calculation.
6. Adding these metrics SHALL NOT change any existing mode's output.
   - Given the existing `cost`, `phase`, `spec`, `estimate` and `mix` modes, when run before and after this change on the same log, then their output is byte-identical.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite comprehension
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

`--suite observability` would be vacuous here — it already passes 22 cases on the
untouched tree — which is the concrete case the new-suite rule exists for. Cases
run over the existing `evals/fixtures/obs-events.jsonl`, plus fixtures with
deliberately missing transitions for acceptance 2. Acceptance 6 is a
golden-output comparison.

## Notes / decisions (append-only)

- Acceptance 3 is not pedantry. Four weak proxies presented as a comprehension
  measurement would be worse than no metric, because a reassuring number
  suppresses the judgment it is standing in for — and `docs/osmani-audit.md`
  §1.3(c) is explicitly a finding about a gap between what is measured and what
  matters. Labelling them honestly keeps the gap visible.
- Re-open rate is the only *lagging* proxy of the four and the most meaningful:
  work re-opened is work the human did not actually understand when they merged
  it. The other three are leading and cheaper.
- This is a prerequisite for the dark lane (§1.4.6) whose auto-close depends on
  revert and re-open rate. Worth building regardless of whether that lane is ever
  authorized.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 7.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
