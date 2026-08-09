---
id: 009
title: Record reverted attempts in LEARNINGS.md so later runs stop repeating them
status: shelved
profile: standard
created: 2026-08-02
depends_on: 004 012
claimed_by:
branch:
pr:
shelved_from: specd
shelved_reason: same reason as 007: check_cmd carries --live, so every build-loop re-run spawns real claude -p calls. Not a dependency for anything. Shelved by applying the owner's 007 ruling to the identical case; restore with tracker.sh restore for an attended session.
shelved_at: 2026-08-09T00:54:35Z
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

1. An abandoned approach SHALL be recorded with all three parts, in a declared on-disk form.
   - **The form, stated because spec 012 must recognise these entries mechanically and neither spec defined them:** ledger entries live under a dedicated `## Attempt ledger` heading in `LEARNINGS.md`, separate from `## Lessons`. Each is a single bullet of the shape `- [<spec id>] tried <what> — dropped because <why>`. The heading is what makes the class recognisable; the bracketed id is what makes the third part machine-checkable.
   - Given an approach that was implemented and then reverted or replaced, when the **build stage** finishes, then the ledger gains such an entry; an entry missing any of the three parts is invalid.
   - The build stage is the actor. It is the only stage that implements and abandons approaches; the review stage sees a finished branch and has nothing to ledger.
2. Transient failures SHALL NOT be ledgered.
   - Given a tool error, a flaky test, or a retry that then succeeded, when the stage finishes, then no ledger entry is created — the ledger records decisions, not noise.
   - Ledger entries are exempt from the file's two-strikes rule (`templates/LEARNINGS.md:6-7`) and record on first occurrence. Recording an abandoned approach only the second time it is abandoned would defeat the entire purpose, which is stopping the second attempt.
3. Stages SHALL consult the ledger before proposing an approach.
   - Given a ledgered approach and a later spec touching the same paths, when a stage proposes work, then the ledger entry is surfaced in its reasoning.
4. Retrying a ledgered approach SHALL be allowed and SHALL be explicit.
   - Given a stage that decides to retry a previously abandoned approach, when it proceeds, then it records why the earlier reason no longer applies — the ledger informs, it does not veto.
5. The ledger SHALL be subject to the file's size discipline, not exempt from it and not the owner of it.
   - Given ledger growth, when the file crosses its cap, then spec 012's consolidation handles ledger entries the same way it handles every other entry — this spec adds entries, it does not manage the file.
   - Given spec 012 not yet landed, when this spec is claimed, then it waits; `depends_on: 012` makes that mechanical rather than a note.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite ledger --live
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

**This spec is attended-only, by owner ruling (2026-08-08), and `--live` is in
the check_cmd deliberately.** Acceptances 3 and 4 concern stage reasoning and
are only observable through a live agent; `evals/run_eval.sh:89-92` skips
headless-agent cases without the flag, and a skipped case never fails a run — so
an earlier draft named those acceptances as needing `--live` while omitting it
from the check. Every run now spends subscription tokens on real agent calls and
the spec cannot be built unattended. Accepted trade.

Acceptances 1 and 2 are mechanically checkable over fixture LEARNINGS files and
need no agent — including a fixture asserting the `## Attempt ledger` heading and
bullet grammar, which is the contract spec 012 consumes. Acceptance 5 is covered
by spec 012's own suite.

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

- 2026-08-08 spec-review: MODIFIED check_cmd to include `--live` (owner ruling). The spec already stated acceptances 3-4 needed it and then omitted it, so the gate could not fail on them. Attended-only from here.
- 2026-08-08 spec-review: ADDED the on-disk ledger form — a `## Attempt ledger` heading and a `- [<spec id>] tried <what> — dropped because <why>` bullet. Spec 012 acceptance 6 requires recognising ledger entries as a class and neither spec had defined how.
- 2026-08-08 spec-review: ADDED the two-strikes exemption and named the build stage as the actor. Both were undefined; the first-occurrence rule is the point of an attempt ledger.
