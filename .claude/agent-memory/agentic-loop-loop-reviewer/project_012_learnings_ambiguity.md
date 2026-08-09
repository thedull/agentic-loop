---
name: project-012-learnings-ambiguity
description: RESOLVED by spec-review 2026-08-08 — near-dup now propose-only, ledger grammar now defined. See [[project_012_learnings_impl_bugs]] for the implementation's own defects.
metadata:
  type: project
---

**Update 2026-08-08 (implementation review):** the spec's own revision log now
shows both gaps closed — acceptance 3 was MODIFIED to make near-duplicates
propose-only (no threshold needed since nothing merges automatically), and
acceptance 6 was MODIFIED to cite spec 009's exact ledger grammar
(`- [<spec id>] tried <what> — dropped because <why>`), which the
implementation exploits by treating every `- ` bullet uniformly regardless of
section. Verified the shipped `scripts/lib/learnings.sh` against both: near-dup
mutation attempts (fuzzy key, post-pass merge, deleting one body) were all
caught by the eval suite; ledger entries merge/survive correctly per case 608.
This memory's original concern no longer applies to spec 012 as merged — kept
below for historical context only.

Spec 012 (`factory/specs/012-learnings-consolidation.md`) acceptance 3
requires merging "duplicates or near-duplicates" and calls this out itself
(Fixtures note, lines 54-59) as the case to mutation-test hardest — yet no
similarity threshold or algorithm is defined anywhere in the spec. Confirmed:
grepped the spec for "threshold|similar|near-dup" and found only the bare
phrase, no definition.

Separately, acceptance 6 requires ledger entries (from spec 009,
`factory/specs/009-attempt-ledger.md`) to be recognized as a class and
consolidated "the same...but not exempt." Neither spec 012 nor spec 009
(acceptance 1, `009:31`) defines an on-disk marker (heading/prefix/tag) that
would let a consolidator tell a ledger entry apart from a lesson bullet.
Confirmed by reading `templates/LEARNINGS.md` in full — only a `## Lessons`
section exists today; no ledger section, no format hint.

**Why this matters:** this is the third spec in the LEARNINGS.md/ledger
family (009, 012) where a downstream spec assumes a data shape ("ledger
entries," "ledger section") that no upstream spec actually pins down. See
also [[project_primary_objective_unenforced_by_checkcmd]] for the general
pattern of specs whose primary mechanism is under-specified.

**How to apply:** when reviewing any future spec that touches
`templates/LEARNINGS.md` or references "the ledger," check whether the format
of a ledger entry (vs. a plain lesson bullet) has been pinned down anywhere
yet. As of 2026-08-08 it has not — flag it again if still open.
