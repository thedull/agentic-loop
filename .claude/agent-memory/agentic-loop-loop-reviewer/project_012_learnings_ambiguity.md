---
name: project-012-learnings-ambiguity
description: spec 012 (learnings-consolidation) never defines near-duplicate similarity or a ledger-entry on-disk format; spec 009's ledger section is likewise unspecified
metadata:
  type: project
---

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
