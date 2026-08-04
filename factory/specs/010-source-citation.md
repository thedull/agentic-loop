---
id: 010
title: Require a cited source for API and framework decisions at build time
status: shelved
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
shelved_from: queued
shelved_reason: Targets scaffolded projects, not the plugin repo, which has no package manager to ground citations against — so the plugin cannot eval the rule it would ship. Review-time detection of hallucinated APIs already works (agents/reviewer.md:42). Restore when a real project hits a hallucinated-API bug worth preventing; that incident should specify the gate. Owner ruling 2026-08-04.
shelved_at: 2026-08-04T06:02:24Z
---

# Spec 010 — Require a cited source for API and framework decisions at build time

## Brief (the delegation contract)

- **objective**: prevent hallucinated APIs at build time by requiring library-behavior decisions to cite current documentation, rather than only detecting them at review time.
- **user_intent_verbatim**: backlog item 6 of `docs/osmani-audit.md` §2.7 — the reviewer's guard checklist catches hallucinated APIs after the fact (`agents/reviewer.md:42-43`); nothing requires grounding before the fact.
- **input_paths**: `skills/build/SKILL.md`, `templates/LOOP_POLICY.md`, `agents/reviewer.md`, `evals/cases/source-citation/`
- **boundaries_non_goals**:
  - Does NOT require a citation for every line. Only decisions that depend on external library or framework behavior.
  - Does NOT mandate network access. Where docs are unreachable, the requirement is satisfied by checking the installed dependency's own source or types — the point is grounding, not fetching.
  - Does NOT add an MCP or a docs service.
  - Does NOT remove the review-time detection. Prevention and detection both stay.
- **output_spec**: a build that makes a decision about external library behavior records what it checked and where, verifiable from the diff and envelope; and an uncheckable decision becomes an assumption rather than a silent choice.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. A decision depending on external library behavior SHALL record its source.
   - Given a build that calls a library API whose behavior determines correctness, when the envelope is emitted, then it records what was consulted — a doc URL with version, or the installed package's own source or type declarations.
2. The installed version SHALL be the authority over recalled knowledge.
   - Given a conflict between what the worker recalls and what the installed dependency provides, when the build proceeds, then the installed dependency wins and the conflict is recorded.
3. An ungroundable decision SHALL become a recorded assumption, not a silent one.
   - Given a decision the worker cannot ground in either docs or installed source, when the envelope is emitted, then it appears in `assumptions[]` with what could not be verified — and given the same situation, then it is never presented as a verified fact.
4. The requirement SHALL be scoped, not universal.
   - Given a change touching only the project's own code, when the envelope is emitted, then no citation is required and its absence is not a finding.
5. Review-time detection SHALL remain.
   - Given a hallucinated API that slipped past the build-time requirement, when the blind review runs, then the existing guard-checklist detection still reports it.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite source-citation
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Acceptances 1, 3 and 4 are mechanically checkable over fixture envelopes and
diffs. Acceptance 2 needs a fixture where the installed dependency genuinely
differs from a plausible recollection.

## Notes / decisions (append-only)

- Acceptance 3 is the load-bearing one, and it is the cheap half of this spec.
  Turning an ungrounded decision into a recorded assumption costs nothing and
  converts an invisible risk into something the evening reviewer can see. The
  citation requirement itself is the more expensive half and the less certain
  payoff.
- Deliberately allowing installed-source inspection to satisfy the requirement
  (boundaries, acceptance 1) rather than demanding a doc URL: the installed
  package is a *better* authority than its documentation, which is frequently
  written for a different version than the one on disk.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 6.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
