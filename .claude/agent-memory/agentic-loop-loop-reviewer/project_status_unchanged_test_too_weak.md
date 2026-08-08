---
name: project-status-unchanged-test-too-weak
description: a case that only asserts "claim exited nonzero AND target status did not change" proves nothing about *why* — it passes identically if the claim path is globally broken for every input, not just the one under test
metadata:
  type: project
---

`evals/cases/profile/208-claim-refuses-dark-and-leaves-status.json` (spec
001) claims a `profile: dark` spec via `tracker.sh claim specd building t`
and checks only `.c != 0 and .status == "specd"`. Confirmed live: replacing
`tracker_claim()`'s body with a bare `return 1` (claim is a no-op for every
spec, not specifically dark ones) and re-running
`./evals/run_eval.sh --suite profile` — case 208 still passes, because a
completely non-functional claim also leaves every file's status unchanged
and exits nonzero.

**Why:** "nothing happened, and the command failed" is the same observable
outcome whether the refusal was targeted (this spec, this reason) or the
whole mechanism is dead. A case built to prove a *specific* refusal path
needs positive evidence tied to the specific input — e.g. the stderr message
naming the fixture's actual value/reason, or a control case proving the same
claim call succeeds on a sibling fixture that should be claimable.

**How to apply:** for any case shaped "action refuses harmlessly, state
unchanged," try neutering the whole action (`return 1` / early-exit stub) and
re-run through the harness. If the case still passes, it isn't proving the
targeted behavior — flag it. See also
[[project_grep_count_mechanical_check_weak]] for the stderr-text sibling of
this failure mode. 1st strike: spec 001.
