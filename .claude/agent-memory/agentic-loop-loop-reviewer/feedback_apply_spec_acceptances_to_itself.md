---
name: feedback-apply-spec-acceptances-to-itself
description: for specs about checking other specs (e.g. 014-spec-internal-consistency), apply the spec's own numbered acceptance criteria to the spec file itself as a review technique
metadata:
  type: feedback
---

When reviewing a spec whose subject matter is "detect inconsistency/drift in a
spec file" (e.g. `factory/specs/014-spec-internal-consistency.md`), literally
apply its own acceptance criteria to itself: check whether every file its
acceptances reference (including fixture examples inside Given/When/Then
bullets, not just the numbered claim text) is listed in its own
`input_paths`, and whether its Notes/Revision-log cite acceptance numbers
that exist.

**Why:** this caught a real hit on first use — spec 014's acceptance 1
fixture bullet cites "spec 011 as it stood at commit d9c6b3a" (i.e.
`factory/specs/011-comprehension-metrics.md`), but that path is absent from
spec 014's own `input_paths` (only `skills/spec/SKILL.md`,
`templates/factory-spec.md`, `scripts/lib/`, `evals/cases/spec-consistency/`
are listed). The same spec that exists to catch exactly this class of gap
has it, uncaught, in its own acceptance text.

**How to apply:** for any "meta" spec whose job is checking other specs'
structure/consistency, treat its own body as the first test case before
reviewing anything else about it. Also verify any fixture commit hashes
named in acceptance text actually exist and say what the spec claims (`git
show <hash>:<path>`) — don't take a cited commit/diff description on faith.
