---
name: feedback-run-checkcmd-dont-just-read-it
description: for spec-gate reviews, always execute the spec's check_cmd against the current tree, don't just eyeball it
metadata:
  type: feedback
---

When reviewing a factory spec's Red Gate `check_cmd`, actually run it in the
repo before judging whether it's vacuous. Reading the command and the target
suite's file list is not sufficient — the eval harness's skip semantics
(`evals/run_eval.sh`: skipped cases never fail a run) can make a suite exit 0
even with zero relevant cases present. This was the strongest, most concrete
finding in the 001-profile-switch spec review: `./evals/run_eval.sh --suite
spec-gate` passes trivially today, before any implementation.

**Why:** the review protocol prioritizes "proof before preference" — an
executed command's output is stronger evidence than inferring pass/fail from
reading JSON case files. This project's eval harness is bash+jq, cheap to
run, no excuse not to.

**How to apply:** for every agentic-loop spec review task, run
`./evals/run_eval.sh --suite <name>` (and `--case <id>` for the specific
guard if named) before writing findings about check_cmd validity. See also
[[project-spec-gate-checkcmd]].
