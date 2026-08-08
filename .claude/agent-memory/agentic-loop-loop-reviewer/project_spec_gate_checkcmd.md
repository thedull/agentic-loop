---
name: project-spec-gate-checkcmd
description: evals/cases/spec-gate/ only has one unrelated headless-agent case — check_cmd "run_eval.sh --suite spec-gate" passes trivially (0 fail) with zero implementation
metadata:
  type: project
---

`evals/cases/spec-gate/` contains exactly one case, `070-ambiguity-caught.json`
(headless-agent, tests the reviewer's general spec-ambiguity-catching skill —
not tied to any specific factory spec's acceptance criteria). Running
`./evals/run_eval.sh --suite spec-gate` without `--live` skips it and exits 0
with "0 pass, 0 fail, 1 skipped" — skips never fail a run
(evals/run_eval.sh:215).

**Why this matters:** any future factory spec whose `check_cmd` is
`./evals/run_eval.sh --suite spec-gate` is vacuous *unless that spec's own
acceptance criteria are elevated to a numbered requirement to add new cases
to that suite*. Spec 001 (`factory/specs/001-profile-switch.md`) only
mentions adding cases in Check-command prose, not as a numbered Acceptance
item — so the gate can never fail regardless of whether the spec is
implemented. Confirmed by running the command directly before any
implementation existed.

**How to apply:** when reviewing any future spec whose check_cmd targets the
`spec-gate` suite (or any suite with sparse/unrelated cases), always run the
command against the current tree first to see whether it already passes
trivially. If it does, that's a high-severity vacuous-check_cmd finding
regardless of how well-written the spec's acceptance criteria otherwise are.
See also [[feedback-run-checkcmd-dont-just-read-it]].
