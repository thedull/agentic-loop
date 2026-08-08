---
id: 009
title: Record reverted attempts in LEARNINGS.md so later runs stop repeating them
status: queued
profile: standard
created: 2026-08-02
depends_on: 004 012
claimed_by:
branch:
pr:
---

# Spec 009 — Record reverted attempts in LEARNINGS.md so later runs stop repeating them

## Brief (the delegation contract)

- **objective**: give the loop a memory of approaches that were tried and abandoned, not just lessons that were learned.
- **user_intent_verbatim**: `docs/osmani-audit.md` §2.3.5 — stolen from `performance-optimization`'s ledger. An unattended loop has no memory of yesterday's failed approach and will cheerfully rediscover it.
- **input_paths**: `templates/LEARNINGS.md`, `skills/build/SKILL.md`, `skills/review/SKILL.md`, `evals/cases/ledger/`
- **boundaries_non_goals**:
  - Does NOT add a database, index, or memory MCP. Files and git remain the memory, per the repo's evidence-backed position.
  - Does NOT record every failed tool call. The ledger is for abandoned *approaches*, not transient errors.
  - Does NOT make the ledger binding. A later run may retry a ledgered approach; it must do so knowingly.
  - Does NOT change the existing two-strikes rule or the file's size cap.
- **output_spec**: an approach that was implemented and then abandoned is recorded with what was tried, why it was dropped, and the spec it came from; and stages consult the ledger before proposing an approach.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. An abandoned approach SHALL be recorded with all three parts.
   - Given an approach that was implemented and then reverted or replaced, when the stage finishes, then the ledger gains an entry naming what was tried, why it was dropped, and the originating spec id; an entry missing any part is invalid.
2. Transient failures SHALL NOT be ledgered.
   - Given a tool error, a flaky test, or a retry that then succeeded, when the stage finishes, then no ledger entry is created — the ledger records decisions, not noise.
3. Stages SHALL consult the ledger before proposing an approach.
   - Given a ledgered approach and a later spec touching the same paths, when a stage proposes work, then the ledger entry is surfaced in its reasoning.
4. Retrying a ledgered approach SHALL be allowed and SHALL be explicit.
   - Given a stage that decides to retry a previously abandoned approach, when it proceeds, then it records why the earlier reason no longer applies — the ledger informs, it does not veto.
5. The ledger SHALL be subject to the file's size discipline, not exempt from it and not the owner of it.
   - Given ledger growth, when the file crosses its cap, then spec 012's consolidation handles ledger entries the same way it handles every other entry — this spec adds entries, it does not manage the file.
   - Given spec 012 not yet landed, when this spec is claimed, then it waits; `depends_on: 012` makes that mechanical rather than a note.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite ledger
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Acceptances 1 and 2 are mechanically checkable over fixture LEARNINGS files and
envelopes; acceptance 5 is covered by spec 012's own suite, asserted here only
as the ledger-entry fixture that suite consumes. Acceptances 3 and 4 concern stage reasoning and belong on the
anchored-rubric or `--live` path.

## Notes / decisions (append-only)

- Acceptance 2's exclusion is what keeps this from becoming a log. A ledger that
  records every transient failure is unreadable within a week and gets ignored,
  which is worse than not having one — the entries that matter get buried by the
  ones that do not.
- Non-binding by design (acceptance 4). A binding ledger would let a
  circumstantially-wrong decision from one bad afternoon permanently foreclose
  the right approach, and the loop has no mechanism to notice that happening.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.3.5.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
- 2026-08-04 grill: MODIFIED acceptance 5 — it asserted an automated consolidation mechanism that does not exist (review-gate finding; the only mechanism was a manual checkbox at RUNBOOK.md:183). Owner chose to build the real thing, so consolidation is now spec 012 and this spec depends on it rather than assuming it.
