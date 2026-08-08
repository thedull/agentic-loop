---
id: 004
title: Make the eval runner fail when it ran nothing
status: specd
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
- **input_paths**: `evals/run_eval.sh`, `evals/README.md`, `evals/cases/`, `skills/build/SKILL.md`
- **boundaries_non_goals**:
  - Does NOT change what any individual case asserts, or any case's pass/fail logic.
  - Does NOT make skips fail. A skipped case in a suite that also ran something is still a skip, and `--live`-only cases must stay skippable.
  - Does NOT add a dependency or a new runner. This is a change to exit-status logic and argument validation.
- **output_spec**: the runner distinguishes "everything I ran passed" from "I ran nothing", exits non-zero for the latter, and rejects a `--suite`/`--case` argument that matches no case.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The runner SHALL exit non-zero when zero cases executed **for an explicitly named suite or case**.
   - Given `--suite X` or `--case Y` where every matching case is skipped, when the runner completes, then it exits non-zero and prints a message distinguishing "no cases ran" from "cases ran and passed".
   - Given a bare `./evals/run_eval.sh` sweep in which some suites are entirely skipped, when it completes, then those skips do not fail the run — a free-tier sweep legitimately skips `--live` cases.
   - Given a bare sweep in which **zero** cases execute across every suite, when it completes, then it exits non-zero. The carve-out above is for *some* suites skipping, not for a run that did nothing at all; a sweep that executes nothing is the same silent success this spec exists to remove, and it is unreachable on today's tree only by accident.
2. The runner SHALL exit non-zero when `--suite` names a suite that does not exist.
   - Given `--suite nosuchsuite`, when the runner completes, then it exits non-zero and names the unmatched argument.
3. The runner SHALL exit non-zero when `--case` names a case that does not exist.
   - Given `--case nonexistent-case-xyz`, when the runner completes, then it exits non-zero and names the unmatched argument.
   - Given `--suite <real suite> --case <id not in that suite>` — whether the id exists nowhere, or exists only in a different suite — when the runner completes, then it exits non-zero. Both combinations exit 0 today (verified: `--suite tracker --case shim-010-ollama-mock-ok` prints 0/0/0 and exits 0), and an explicitly named filter matching nothing is the same defect regardless of how many filters were named.
   - A suite directory that exists but contains no case files SHALL be treated identically to a suite that does not exist. `evals/run_eval.sh:203-211` cannot distinguish them — both `continue` — and inventing a distinction would mean inventing information the runner does not have.
4. The runner SHALL continue to exit zero when at least one case executed and none failed.
   - Given a suite with one passing bash-unit case and one skipped `--live` case, when the runner completes, then it exits zero.
5. A full free-tier run SHALL be unaffected.
   - Given `./evals/run_eval.sh` with no arguments on the untouched tree, when it completes, then it exits zero, because at least one free case runs.
6. "Nothing ran" SHALL use its own exit code, distinct from a failing case.
   - Given any of acceptances 1–3, when the runner exits, then the code is 4, not 1; and given a run where a case genuinely failed, then the code is 1.
   - This lets a caller distinguish "your gate is not wired up" from "your gate caught a real failure". During the Red Gate both are non-zero, but only one means the spec is healthy — a typo'd suite name would otherwise be indistinguishable from a correctly failing test.
7. The Red Gate SHALL require a genuinely failing test, not an absent one.
   - Given the build stage running `check_cmd` before implementation, when the command exits 4 ("nothing ran"), then the Red Gate is NOT satisfied and the stage refuses — "no test" is not "a failing test".
   - Given the same stage, when `check_cmd` exits 1 because real cases ran and failed, then the Red Gate is satisfied and building may proceed.
   - Consequence for build order, which the build skill must state: the builder writes the suite and its cases FIRST, runs the check to see real failures, and only then implements.
   - **This acceptance SHALL be verified mechanically, not by having edited the file.** `skills/build/SKILL.md:44-50` today says only that `check_cmd` "MUST fail", with no exit-code branch — so a builder reading it literally would accept exit 4 as satisfying the Red Gate, which is the exact inversion this spec forbids. A case in the `evalrunner` suite SHALL assert that the build skill's Red Gate step distinguishes exit 4 from exit 1, and SHALL fail if that distinction is absent. A prose edit nothing checks is not a deliverable this spec can claim.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite evalrunner
```

A new suite directory `evals/cases/evalrunner/` holds bash-unit cases that
invoke the runner as a subprocess and assert its exit status — the runner
testing itself, one level down.

**Do not read this check_cmd as already red.** An earlier draft of this section
claimed it "fails before the work because the suite does not exist yet." That is
false and the Notes below always said so: run today it prints `0 pass, 0 fail, 0
skipped` and exits **0**, because the zero-case guard is the very thing this spec
adds. Acceptance 2 cannot be the reason the check currently fails — acceptance 2
*is* the work.

So the Red Gate here is satisfied the ordinary way and not by a special case: the
builder writes `evals/cases/evalrunner/` and its cases first, runs the check, and
sees genuine failures (exit 1) from cases asserting behaviour the runner does not
yet have. Only then implement. The recursion is sound because each case invokes
the runner as a **subprocess** and asserts its exit status, so the copy under
test is observed from outside rather than judging itself.

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
- **The rule this unlocks, which every downstream spec now follows:** a spec's
  `check_cmd` should name a **new suite of its own**, never an existing one.
  Measured on the untouched tree: `--suite tracker` passes 24 cases and
  `--suite observability` passes 22, so either would exit 0 before any work and
  fail the Red Gate as vacuous. Worse, two specs adding cases to one shared
  suite make each other's gate vacuous depending on claim order, which is a
  silent, order-dependent failure — the hardest kind to notice. A per-spec suite
  fails for the honest reason that it does not exist yet (acceptance 2 and 3 are
  what make that a failure), and passes only when that spec's own cases run.
  This belongs in `docs/factory.md` alongside the Red Gate description, not just
  in this Notes block.
- Bootstrapping, restated after grilling (2026-08-03): acceptance 7 resolves what
  was previously a fudge. This spec's `check_cmd` names a suite that does not
  exist, and on the untouched tree that currently exits 0 — which the Red Gate
  correctly reads as vacuous and blocks. The builder's first implementation step
  is therefore to create `evals/cases/evalrunner/` and its cases, run the check,
  and see them genuinely fail; only then does the runner change get written. That
  is the same order acceptance 7 now imposes on every spec, so this spec is not a
  special case — it is the first instance of the rule.

- **Exit 4 is a reused numeral, and that is accepted deliberately.** It already
  means "envelope failed schema validation" in `scripts/lib/common.sh:90` (reached
  by every shim through `finalize_envelope`) and "no judge tier available" in
  `evals/judge.sh:48`. There is no mechanical collision — those exits happen in
  different processes, shim exit codes are captured per-case, and judge.sh's is
  swallowed by its own pipeline — and nine downstream specs already quote `exits
  4 ("nothing ran")` verbatim, so renumbering now would cost more than the
  overload does. Recorded because a future reader grepping for `exit 4` will find
  three meanings and should know that was noticed rather than missed.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED after the spec-review gate on 001/002/003 found all three check_cmds vacuous and traced it to the runner rather than to the specs.
- 2026-08-08 spec-review: FIRST pass through this gate — the spec that blocks fourteen others had never been reviewed. Six findings, all applied.
- 2026-08-08 spec-review: MODIFIED the Check-command section, which claimed this check_cmd already fails before the work. It exits 0; the Notes section had said so all along and the two contradicted each other. The recursion is now stated as sound-because-subprocess rather than asserted.
- 2026-08-08 spec-review: MODIFIED acceptance 7 to require a mechanical check on `skills/build/SKILL.md`'s Red Gate step. It was a prose edit no check_cmd could verify — the gate flagged this as the second instance of that pattern in this project.
- 2026-08-08 spec-review: ADDED the combined `--suite X --case Y` zero-match path and the empty-but-present suite directory to acceptance 3; both exit 0 today and neither was covered.
- 2026-08-08 spec-review: ADDED the fully-degenerate bare sweep to acceptance 1. The carve-out covered *some* suites skipping, not a run that executed nothing.
- 2026-08-08 spec-review: ADDED a Notes entry acknowledging that exit 4 already carries two other meanings in the repo, and why keeping it is the cheaper choice.
