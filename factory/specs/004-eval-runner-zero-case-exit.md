---
id: 004
title: Make the eval runner fail when it ran nothing
status: queued
profile: standard
created: 2026-08-02
depends_on:
claimed_by:
branch:
pr:
---

# Spec 004 — Make the eval runner fail when it ran nothing

## Brief (the delegation contract)

- **objective**: make `evals/run_eval.sh` exit non-zero when it executed zero cases, so that `--suite <name>` is a usable `check_cmd` oracle.
- **user_intent_verbatim**: found by the spec-review gate on specs 001/002/003 (2026-08-02). All three reviewers independently ran their proposed `check_cmd` and found it already exited 0 on the untouched tree. Investigation then showed the cause is broader than skipped cases: `./evals/run_eval.sh --suite nosuchsuite` and `--case nonexistent-case-xyz` both print "0 pass, 0 fail" and exit 0.
- **input_paths**: `evals/run_eval.sh`, `evals/README.md`, `evals/cases/`
- **boundaries_non_goals**:
  - Does NOT change what any individual case asserts, or any case's pass/fail logic.
  - Does NOT make skips fail. A skipped case in a suite that also ran something is still a skip, and `--live`-only cases must stay skippable.
  - Does NOT add a dependency or a new runner. This is a change to exit-status logic and argument validation.
- **output_spec**: the runner distinguishes "everything I ran passed" from "I ran nothing", exits non-zero for the latter, and rejects a `--suite`/`--case` argument that matches no case.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The runner SHALL exit non-zero when zero cases executed.
   - Given a suite whose every case is skipped, when the runner completes, then it exits non-zero and prints a message distinguishing "no cases ran" from "cases ran and passed".
2. The runner SHALL exit non-zero when `--suite` names a suite that does not exist.
   - Given `--suite nosuchsuite`, when the runner completes, then it exits non-zero and names the unmatched argument.
3. The runner SHALL exit non-zero when `--case` names a case that does not exist.
   - Given `--case nonexistent-case-xyz`, when the runner completes, then it exits non-zero and names the unmatched argument.
4. The runner SHALL continue to exit zero when at least one case executed and none failed.
   - Given a suite with one passing bash-unit case and one skipped `--live` case, when the runner completes, then it exits zero.
5. A full free-tier run SHALL be unaffected.
   - Given `./evals/run_eval.sh` with no arguments on the untouched tree, when it completes, then it exits zero, because at least one free case runs.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite evalrunner
```

A new suite directory `evals/cases/evalrunner/` holds bash-unit cases that
invoke the runner as a subprocess and assert its exit status — the runner
testing itself, one level down. This `check_cmd` fails before the work for the
honest reason that the suite does not exist yet (acceptance 2 is what makes that
a failure rather than a silent pass), and passes after.

Every guard is mutation-tested: remove the zero-case check, confirm the case
fails.

## Notes / decisions (append-only)

- This is a silent-success bug, the same class as an HTTP 200 whose body says
  the write was rejected: the status code reports on the transport, not on the
  work. A runner that answers "fine" to "I matched nothing" makes every
  suite-scoped `check_cmd` in every downstream spec vacuous, which is precisely
  the failure the Red Gate exists to prevent — so the harness was undermining
  the guarantee it is supposed to enforce. `docs/factory.md` already names this:
  the harness needs the same rigor as the product.
- Bootstrapping note, stated rather than hidden: this spec's own `check_cmd`
  depends on acceptance 2 being implemented, since "suite does not exist" is
  only a failure once unmatched arguments are an error. That is a genuine
  chicken-and-egg, resolved by the build stage running the check first (it fails
  because the suite is absent and the tree is untouched — currently by exiting 0,
  which the Red Gate reads as vacuous and blocks). The builder must therefore
  create the suite directory and its first case as the *first* implementation
  step, then re-run.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED after the spec-review gate on 001/002/003 found all three check_cmds vacuous and traced it to the runner rather than to the specs.
