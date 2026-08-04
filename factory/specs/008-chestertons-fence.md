---
id: 008
title: Require a reason before the minimize ladder deletes anything
status: shelved
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
shelved_from: queued
shelved_reason: Guards the minimize ladder, which the owner does not run (default-off flag). Protects an unused path; restore if minimize is ever enabled. Owner ruling 2026-08-04 during spec grilling.
shelved_at: 2026-08-04T05:58:29Z
---

# Spec 008 — Require a reason before the minimize ladder deletes anything

## Brief (the delegation contract)

- **objective**: put Chesterton's Fence in front of the minimize ladder's deletion rungs — establish why code exists before removing it.
- **user_intent_verbatim**: `docs/osmani-audit.md` §2.3.4 — stolen from `code-simplification`. The ladder's first rung is "does this need to exist at all?" and it has no counterweight except the hard exception for validation, error handling and security.
- **input_paths**: `agents/worker-cheap.md`, `skills/build/SKILL.md`, `evals/cases/fence/`
- **boundaries_non_goals**:
  - Does NOT disable or weaken the minimize ladder. It gates one class of move — removal — not the whole ladder.
  - Does NOT apply to code the same change introduced. Deleting your own scaffolding from ten minutes ago needs no archaeology.
  - Does NOT require network access or issue-tracker lookups. Blame, comments, tests and call sites are the evidence sources.
  - Does NOT change the existing hard exception (never trim validation, error handling, or security to get smaller) — that stays absolute and independent of this gate.
- **output_spec**: a removal in minimize mode is accompanied by a recorded reason the code existed, or it does not happen.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. A removal SHALL cite why the removed code existed.
   - Given minimize mode removing pre-existing code, when the change is made, then the worker's envelope records the evidence consulted — blame, a covering test, a comment, or the absence of call sites — and what it concluded.
2. Absence of evidence SHALL block the removal, not permit it.
   - Given code whose purpose the worker cannot establish from available evidence, when minimize mode considers removing it, then it is left in place and recorded as a candidate for the human, rather than removed on the grounds that no reason was found.
3. The gate SHALL apply only to pre-existing code.
   - Given code introduced by the same change, when it is removed, then no fence evidence is required.
4. The existing hard exception SHALL remain independent and absolute.
   - Given validation, error-handling, or security code, when minimize mode considers it, then it is not removed regardless of how good the fence evidence is — a satisfied fence never unlocks the exception.
5. The reviewer SHALL be able to check the fence from the diff and envelope alone.
   - Given a diff containing a removal and its envelope, when the blind review runs, then it can determine whether the fence was satisfied without re-deriving the archaeology itself.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite fence
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Fixture pairs drive it: a removal with evidence, a removal without, a removal of
same-change code, and a removal of code covered by the hard exception.
Mutation-test acceptance 2 hardest — its failure mode (no reason found,
therefore safe to delete) is the exact inversion of the rule.

## Notes / decisions (append-only)

- Acceptance 2 is the whole spec. "I could not find a reason for this code" is
  the single most common justification an unattended worker will produce for
  deleting something load-bearing, and it is precisely backwards: a haiku-tier
  worker looking at one diff has almost no ability to see why code matters
  elsewhere in the system. Inverting the default is cheap and the failure it
  prevents is expensive.
- Keeping the hard exception independent (acceptance 4) rather than folding it
  into the fence avoids a subtle regression: a worker that finds good evidence
  for why a validation check exists must still not remove it, and a single
  merged rule would invite exactly that reasoning.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.3.4.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
