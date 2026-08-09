---
id: 012
title: Automate LEARNINGS.md consolidation instead of trusting a checkbox
status: pr-open
profile: standard
created: 2026-08-04
depends_on: 004
claimed_by: auto-loop
branch:
pr: https://github.com/thedull/agentic-loop/pull/7
claimed_at: 2026-08-09T00:30:06Z
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
   - The cap SHALL live in one machine-readable place. Today `~300 lines` exists only as prose in `templates/LEARNINGS.md:9`, `templates/LOOP_POLICY.md:136` and `templates/RUNBOOK.md:183`, so nothing can read it. A declared constant is part of this work.
   - Given a `LEARNINGS.md` over the declared cap, when the check runs, then it reports the overage and the **line count** of the file; and given one under, then it reports clean and exits zero.
   - `doctor.sh` surfaces this, so an over-cap file is visible during preflight rather than discovered when someone remembers the checkbox.
2. Consolidation SHALL be explicit, never automatic.
   - Given an over-cap file, when the check runs, then it does not modify anything; and given the consolidate action invoked deliberately, then it rewrites the file.
3. Consolidation SHALL merge only what is decidable, and SHALL propose the rest.
   - **Exact duplicates are merged; near-duplicates are proposed, never merged automatically.** "Near-duplicate" is a judgment, and this repo's rule is that a gate refuses on decidable facts while a reviewer judges — the same routing spec 014 settled. A consolidator that silently merges on a similarity threshold destroys distinct learnings whenever the threshold is wrong, and nothing later can tell.
   - Given byte-identical or whitespace-only-differing entries, when consolidation runs, then they are merged into one retaining the earliest date.
   - Given entries that merely resemble one another, when consolidation runs, then they are listed as merge candidates for a human to accept or reject, and the file is not changed on their account.
   - Given entries that are genuinely distinct, then all of them survive.
4. Consolidation SHALL be reversible without depending on git.
   - Given a consolidation run, when it completes, then the pre-consolidation file is preserved as a timestamped copy alongside it. "Committed first" is explicitly NOT an acceptable form: the eval sandbox is a bare `mktemp -d` with no git, so a git-based reversibility branch could never be verified by any case.
5. An LLM SHALL NOT be required.
   - Given no model available, when consolidation runs, then it still functions on the mechanical cases — exact and near-duplicate merging, and ordering. A model may be offered to propose merges for review, but consolidation must not depend on one.
6. The ledger section from spec 009 SHALL be consolidated by the same mechanism.
   - Ledger entries are recognised by spec 009's declared form: bullets under a `## Attempt ledger` heading, shaped `- [<spec id>] tried <what> — dropped because <why>`. That grammar is the contract between the two specs and neither could recognise the class without it.
   - Given a `LEARNINGS.md` containing ledger entries, when consolidation runs, then they are subject to the same merging and cap as every other entry — one discipline for the file, not two.

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

- 2026-08-08 spec-review: MODIFIED acceptance 3 — near-duplicate merging is now a proposal, not an automatic merge. The criterion was entirely undefined while the spec called it the hardest case, and an undefined similarity threshold inside a gate is judgment in a place this repo puts refusals.
- 2026-08-08 spec-review: MODIFIED acceptance 4 — "committed first" removed. The bash-unit sandbox is a bare mktemp with no git, so that branch was unverifiable by any case.
- 2026-08-08 spec-review: MODIFIED acceptance 1 — the ~300 cap exists only as prose in three files; a machine-readable constant is now part of the work, and "the count" is the file's line count.
- 2026-08-08 spec-review: MODIFIED acceptance 6 to name spec 009's `## Attempt ledger` grammar. Neither spec defined how ledger entries were recognisable.
- 2026-08-08 build: BUILT on `claude/idea-012-learnings-consolidation`. Red Gate honoured: 11 cases first, 11 genuine failures, then implemented.
- 2026-08-08 review: FIXED silent data loss. Entry slots were marked in the output stream with a literal `\000ENT:<i>` string, so a real content line matching that shape was dropped without warning. Sentinels are gone from the data path entirely — two parallel arrays carry the line and what it is.
- 2026-08-08 review: FIXED a crash on an empty file. `set -u` plus bash 3.2's empty-array semantics made `${out[@]}` an unbound-variable error, and bash 3.2 is what `#!/usr/bin/env bash` resolves to on this machine.
- 2026-08-08 review: MODIFIED case 609 from a grep for the string "learnings.sh" to running `doctor.sh` and asserting it actually warns on an over-cap file. The prior version passed against a comment stating the tool was not called.
- 2026-08-08 build: ADDED the never-INVENTS half of the contract to case 611. Never-loses alone missed a corruption that emitted a line absent from the source while keeping line counts equal — every output line must now appear in the pre-consolidation backup.
