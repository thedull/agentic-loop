---
id: 011
title: Report the comprehension proxies from the event log
status: specd
profile: standard
created: 2026-08-02
depends_on: 004 013
claimed_by:
branch:
pr:
---

# Spec 011 — Report the comprehension proxies from the event log

## Brief (the delegation contract)

- **objective**: add a comprehension metric family to `observe_metrics.sh`, reading the fields spec 013 captures plus the transitions already recorded.
- **user_intent_verbatim**: backlog item 7 of `docs/osmani-audit.md` §2.7, closing finding §1.3(c) — the observability plane measures cost, latency, errors, tokens and cycle time, and measures nothing about how much of what ships anyone still understands.
- **input_paths**: `scripts/lib/obs_metrics.jq`, `scripts/observe_metrics.sh`, `templates/observability/dashboards.md`, `evals/cases/comprehension/`
- **boundaries_non_goals**:
  - Does NOT add event types or change the envelope. Diff size and finding count are captured by spec 013; this spec only reads them. The boundary held — what changed is that the capture it assumed is now a real prerequisite instead of a false premise.
  - Does NOT claim to measure comprehension. These are proxies, and the output must say so — a number labelled "comprehension" would be a fabrication of exactly the kind `lib/obs.sh` refuses.
  - Does NOT add alerting or thresholds. Reporting only.
  - Does NOT regenerate dashboards by hand; the generator derives them from `dashboards.md` as today.
- **output_spec**: a `comprehension` mode reporting diff size per spec, review-finding density per 100 changed lines, human merge latency, and build churn, each with an explicit null when its source data is absent.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. The mode SHALL report four proxies, each read from captured data and none computed from absent data.
   - Given an event log with merged specs, when `comprehension` runs, then it reports diff size per spec (from spec 013), review findings per 100 changed lines (from spec 013), the `pr-open → done` segment, and build churn per spec.
   - "Per unit of diff" is fixed at per-100-changed-lines so the number is comparable across specs rather than defined per implementer.
2. Missing data SHALL produce null, never a computed-from-nothing value.
   - Given a spec with no `pr-open` transition recorded, when the mode runs, then its merge latency is null and is rendered as null — following the existing honest-nulls rule.
3. The output SHALL label the numbers as proxies.
   - Given any rendering of these metrics, when it is read, then it names them as proxies for comprehension debt rather than as a measurement of it.
4. The mode SHALL accept the same window and format flags as the existing modes.
   - Given `--since`, `--until`, and `--format tsv`, when the mode runs, then it behaves consistently with `cost`, `phase`, `spec` and `mix`.
5. Build churn SHALL be named for what it measures, and SHALL NOT be described as a post-merge signal.
   - Given the existing `reopens` field, when it is surfaced here, then it is labelled build churn — transitions back into `building` before merge — because that is what `scripts/lib/obs_metrics.jq:88` actually counts.
   - Given any rendering, when it is read, then nothing claims this measures work re-opened after merge. `done` is terminal in the tracker; no post-merge signal exists to report, and inventing one from a pre-merge counter would be exactly the fabrication the honest-nulls rule forbids.
6. Merge latency SHALL reuse the existing cycle-time segment rather than recomputing it.
   - Given the two-segment cycle time already implemented, when merge latency is reported, then it is the same `pr-open → done` segment, not a second and potentially divergent calculation.
7. Adding these metrics SHALL NOT change any existing mode's output.
   - Given the existing `cost`, `phase`, `spec`, `estimate` and `mix` modes, when run before and after this change on the same log, then their output is byte-identical.

7. Multi-cycle specs SHALL report the last cycle, and SHALL disclose that they did.
   - Given a spec that went `reviewing → building → reviewing` before merge, when its diff size and finding count are reported, then the values from the **final** cycle are used, not a sum and not the first — a sum would double-count code that was rewritten rather than added.
   - Given such a spec, when it is reported, then its reopen count is shown alongside, so a single-cycle and a five-cycle spec are never presented as comparable.
8. The density denominator SHALL be defined, and a zero denominator SHALL be null.
   - Given "review findings per 100 changed lines", when it is computed, then the denominator is **added + removed** lines, since spec 013 captures them separately and either alone understates the change.
   - Given a denominator of zero, when the metric is computed, then it is null rather than a division error or an infinity — a review of a zero-line diff has no density.

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
- Build churn is NOT the lagging proxy I originally claimed (owner ruling
  2026-08-04, off a review-gate finding). `reopens` counts pre-merge cycling,
  which is a real signal about spec quality but says nothing about what the
  human understood at merge time. All four proxies are therefore leading
  indicators, and §1.3(c)'s lagging signal — post-merge revert — stays unbuilt,
  because the tracker has no post-merge state to hang it on. Naming that gap
  beats papering it with a differently-shaped number.
- The dark lane's auto-close (§1.4.6) was specified against revert rate, which
  the point above establishes does not exist. That is a real dependency gap for
  the dark lane (spec 015, unwritten), not something this spec papers over — recorded here so it is
  found before the lane is designed rather than after.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 7.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
- 2026-08-04 grill: MODIFIED — the claim that all four proxies were already captured was disproved by the review gate; diff size and finding count are captured nowhere. Capture split into spec 013 (owner ruling), which this now depends on.
- 2026-08-04 grill: MODIFIED the re-open proxy to build churn, named for what obs_metrics.jq:88 actually counts (owner ruling). Removed the post-merge framing; recorded that the lagging signal stays unbuilt and why.
- 2026-08-04 grill: ADDED a fixed unit (per 100 changed lines) for finding density, which the review flagged as undefined.
- 2026-08-04 grill: MODIFIED the Brief's objective and output_spec, which still carried the disproved "already captures" claim and the old re-open naming after the acceptances had been corrected.
- 2026-08-08 spec-review: ADDED acceptance 7 — reopen-cycle aggregation was unstated, and `obs_metrics.jq:88-89` already counts reopens, so multi-cycle specs are real. Last cycle wins, with the reopen count disclosed beside it.
- 2026-08-08 spec-review: ADDED acceptance 8 — the density denominator was undefined against 013's two separate numbers, and a zero denominator had no stated behaviour.
- 2026-08-08 spec-review: MODIFIED the fixture list to cover acceptance 2's null pass-through, which it had skipped.
