---
id: 012
title: Automate LEARNINGS.md consolidation instead of trusting a checkbox
status: queued
profile: standard
created: 2026-08-04
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 012 — Automate LEARNINGS.md consolidation instead of trusting a checkbox

## Brief (the delegation contract)

- **objective**: give `LEARNINGS.md` a mechanical size discipline, so its stated ~300-line cap is enforced rather than remembered.
- **user_intent_verbatim**: split out of spec 009 during grilling (owner ruling 2026-08-04). The review gate found spec 009 citing automated consolidation that does not exist — the only mechanism is a manual checkbox at `templates/RUNBOOK.md:183`. The owner chose to build the real thing rather than weaken the acceptance.
- **input_paths**: `templates/LEARNINGS.md`, `templates/RUNBOOK.md`, `scripts/lib/`, `evals/cases/learnings/`
- **boundaries_non_goals**:
  - Does NOT delete a learning outright. Consolidation merges and compresses; anything genuinely dropped is dropped by a human.
  - Does NOT summarize with an LLM by default. The cap is a mechanical concern and the file is the loop's memory — a lossy rewrite of memory is a worse failure than an oversized file.
  - Does NOT change the two-strikes rule that governs what earns an entry.
  - Does NOT run inside a build or review stage. Consolidation is a maintenance action, not a per-spec one.
- **output_spec**: a command that reports whether `LEARNINGS.md` is over cap and, when asked, consolidates it — deterministically, reversibly, and without an agent rewriting the content.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The cap SHALL be checked mechanically and reported.
   - Given a `LEARNINGS.md` over the declared cap, when the check runs, then it reports the overage and the count; and given one under, then it reports clean and exits zero.
   - `doctor.sh` surfaces this, so an over-cap file is visible during preflight rather than discovered when someone remembers the checkbox.
2. Consolidation SHALL be explicit, never automatic.
   - Given an over-cap file, when the check runs, then it does not modify anything; and given the consolidate action invoked deliberately, then it rewrites the file.
3. Consolidation SHALL be lossless with respect to distinct learnings.
   - Given entries that are duplicates or near-duplicates of one another, when consolidation runs, then they are merged into one entry retaining every distinct fact and the earliest date; and given entries that are genuinely distinct, then all of them survive.
4. Consolidation SHALL be reversible.
   - Given a consolidation run, when it completes, then the pre-consolidation file is preserved (timestamped alongside, or committed first) so a bad merge can be recovered without git archaeology.
5. An LLM SHALL NOT be required.
   - Given no model available, when consolidation runs, then it still functions on the mechanical cases — exact and near-duplicate merging, and ordering. A model may be offered to propose merges for review, but consolidation must not depend on one.
6. The ledger section from spec 009 SHALL be consolidated by the same mechanism.
   - Given a `LEARNINGS.md` containing ledger entries, when consolidation runs, then ledger entries are subject to the same merging and cap as every other entry — one discipline for the file, not two.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite learnings
```

**Build order (spec 004 acceptance 7).** New suite of its own; a missing suite
exits 4 and is not a valid red. Write the suite and its cases first, see them
genuinely fail, then implement.

Fixtures: an under-cap file, an over-cap file, a file with exact duplicates, one
with near-duplicates, one with only distinct entries (which must survive
consolidation unchanged), and one containing ledger entries. Acceptance 3 is the
one to mutation-test hardest — a consolidator that quietly drops a distinct
learning passes a naive line-count assertion while destroying the thing the file
exists for.

## Notes / decisions (append-only)

- Split from spec 009 rather than folded into it (owner ruling 2026-08-04). The
  ledger needs a bounded file; making the ledger spec also fix the file's
  long-standing size problem would have been two concerns in one seam, and the
  size problem predates the ledger by months.
- No-LLM-required (acceptance 5) is the load-bearing constraint. `LEARNINGS.md`
  is the loop's cross-run memory; a model rewriting it is a lossy compression of
  the one artifact that exists to stop the loop repeating itself, and a bad
  compression would be invisible until the loop repeated a mistake it had
  already recorded.
- Reversibility (acceptance 4) exists for the same reason. Consolidation is the
  only operation in this repo that deliberately destroys detail, so it is the
  one that most needs an undo.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-04 spec: ADDED, split out of spec 009 under grilling after the review gate found 009 citing a consolidation mechanism that does not exist.
