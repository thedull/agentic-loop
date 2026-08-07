---
name: project-codex-subscription-doc-citation-drift
description: docs/codex-subscription.md has a recurring pattern of prose claims (ratios, cross-refs, embellished citations) drifting from the tables/lines they cite, even when the tables themselves check out
metadata:
  type: project
---

`docs/codex-subscription.md` is under active, section-by-section review (§7
added on top of an already-reviewed §1–§6). Two independent reviews now found
the same defect class: the underlying data (tables, `file:line` citations) is
usually accurate, but **prose built on top of that data drifts** — a ratio
computed from rounded display values instead of the exact figures, a `§6
item N` cross-reference pointing at the wrong row, a citation that supports
only part of the sentence it's attached to.

Confirmed instances (2026-08-07 review of §7):
- §7.5 line 513 says "`§6 item 5` proposes it as the `hardened` payload" —
  item 5 in the §6 table (line 350) is the quota re-grounding item; the
  hardened-payload proposal is item 9 (line 354).
- §7.2's "DeepSeek V4 Flash 49×" (line 454) cheaper claim reproduces only by
  dividing the table's *rounded* display costs ($0.245/$0.005); the actual
  ratio from unrounded lean costs is ~53×. The other four ratios in the same
  sentence (8.5×, 3.3×, 17×, 6×) all check out against the unrounded costs,
  making the 49× figure an outlier, not the method.
- §7.1 line 421 cites `templates/LOOP_POLICY.md:202` for "the terminal state
  is an open PR reviewed in the morning" — line 202 only says "Terminal
  state is an open PR, never a merge"; "reviewed in the morning" is not
  sourced anywhere in that file.

An earlier review (referenced in this review's own task spec) separately
found a citation covering only part of its claim and two off-by-N line
numbers in an earlier pass over the same document.

**Why:** the doc's authoring process apparently re-derives narrative
sentences from tables/citations by eye rather than recomputing/re-grepping
each time a new paragraph references them, so drift accumulates each time a
new section is appended.

**How to apply:** when reviewing further additions to this document (or
similar owner-authored analysis docs in this repo with dense
table+citation+backlog cross-referencing), always (a) recompute ratios from
the underlying unrounded numbers, never from the table's rounded display
cells, and (b) re-grep every `§N item M` / `fileX:line` citation against the
actual current section/table, even when it looks superficially plausible.
The tables/base data tend to be correct; the sentences wrapped around them
are where errors live.
