---
name: reviewer-scoping-precedent
description: agents/reviewer.md already has precedent for bolt-on structural sweeps beyond protocol rule 3's "ONLY correctness and requirement gaps" — relevant when judging whether a spec conflicts with reviewer.md:25-27
metadata:
  type: project
---

`agents/reviewer.md` (== this agent's own system prompt) has, at protocol
rule 3 (lines 25-27), "Report ONLY correctness and requirement gaps. Not
style, not taste, not hypothetical improvements." But the same file already
contains a "Guard checklist (flag-gated)" section (lines 36-47) that bolts
on a fixed, unrelated-to-the-task-spec sweep (swallowed errors, hallucinated
APIs, premature abstraction, etc.) whenever `guards.enabled` is true.

**Why it matters:** when a later spec (e.g. 007's presumptive-blocker sweep)
proposes adding another always-on or flag-gated sweep for a closed,
enumerated list of structural problems, it is NOT a textual contradiction
with rule 3 — the file already establishes that rule 3 governs open-ended
judgment calls (style/taste/hypothetical improvements) while bolt-on
sections with a *closed* list are treated as a distinct, sanctioned
carve-out. Confirmed 2026-08-02 while reviewing spec 007 against the task's
explicit ask to check for this conflict.

**How to apply:** don't flag "conflicts with reviewer.md:25-27" as a hard
contradiction just because a spec adds a new sweep instruction to this file
— check first whether the new sweep is closed/enumerated (sanctioned,
follows Guard-checklist precedent) versus open-ended (a real rule-3
conflict). Do still flag if the spec fails to state *where/how* the new
section is inserted relative to the numbered protocol list — that's a
documentation-placement ambiguity, not a scope contradiction.
