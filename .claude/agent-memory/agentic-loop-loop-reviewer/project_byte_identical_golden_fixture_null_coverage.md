---
name: project_byte_identical_golden_fixture_null_coverage
description: "existing modes byte-identical" golden-comparison cases (spec 011 case 806 pattern) are only as strong as the shared fixture's field coverage — a fixture with every est_cost_usd/duration_ms/tier null makes cost/phase mode mutations invisible
metadata:
  type: project
---

Spec 011 acceptance 7 ("adding this mode changes no existing mode's byte
output") is checked by `evals/cases/comprehension/806-existing-modes-byte-identical.json`,
which shells the CURRENT `observe_metrics.sh` against `main`'s
`obs_metrics.jq` over the SAME shared fixture
(`evals/fixtures/comprehension/events.jsonl`) used for every other
comprehension case.

That fixture has `est_cost_usd`, `duration_ms`, and `tier` all `null` on
every single event (verified: `jq -c '{event,est_cost_usd,duration_ms,tier}'`
over the file — every row is null/null/null). Live-mutated
`scripts/lib/obs_metrics.jq`'s `cost` def to double `metered_usd`
(`add | nz | . * 2`) and re-ran `./evals/run_eval.sh --suite comprehension`
in the actual harness sandbox (mktemp cwd, same env as run_eval.sh's
bash-unit runner) — case 806 still passed, because `$metered` is always an
empty array against this fixture (0*2 == 0). By contrast, mutating
`spec_rollup`'s `reopens` formula (which the fixture DOES exercise via
tracker_transition timestamps) was correctly caught by 806.

**Why:** a golden byte-comparison test's real coverage is bounded by which
fields the shared fixture actually varies — a fixture built to exercise ONE
new mode's happy path can silently leave large swaths of the "existing
modes must not change" surface (cost $, phase duration percentiles,
llm_errors, tier splits) completely unverified.

**How to apply:** when reviewing a golden/byte-identical acceptance, don't
just confirm the test framework logic is sound — check whether the shared
fixture populates every field the compared modes actually read. If a field
is null everywhere, that field's logic is unprotected by the golden check
regardless of how good the harness is. See [[project_grep_count_mechanical_check_weak]]
for the sibling pattern (mutate-and-rerun beats reading the assertion).
