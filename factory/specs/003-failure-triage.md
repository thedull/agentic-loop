---
id: 003
title: Triage build failures before blocking, and treat tool output as data
status: done
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by: auto-loop
branch:
pr: https://github.com/thedull/agentic-loop/pull/5
claimed_at: 2026-08-08T09:15:09Z
---

# Spec 003 — Triage build failures before blocking, and treat tool output as data

## Brief (the delegation contract)

- **objective**: put a bounded diagnostic step between a failing `check_cmd` and `blocked`, and state once that tool, error, and external-model output is data rather than instructions.
- **user_intent_verbatim**: backlog item 3 of `docs/osmani-audit.md` §2.7, absorbing the surviving half of §2.3.2 — today two failed attempts go straight to `blocked` with no prescribed diagnosis, and "try again" is the strategy an LLM defaults to.
- **input_paths**: `skills/build/SKILL.md`, `templates/LOOP_POLICY.md`, `agents/reviewer.md`, `evals/cases/triage/`
- **boundaries_non_goals**:
  - Does NOT raise the retry budget. Triage informs the second attempt; it does not buy a third.
  - Does NOT let the triage subagent edit anything. It reports a hypothesis; the builder fixes. Same separation as `agents/reviewer.md`.
  - Does NOT introduce an unbounded diagnose→retry loop — that is the critique→revise loop this repo already rejected (`templates/LOOP_POLICY.md:79`).
  - Does NOT add a debugging skill. The discipline goes inside the existing build stage.
  - Does NOT change the `blocked` state itself, its tracker transition, or any other stage's reading of it. It does add a required Notes artifact before that transition is legitimate.
- **output_spec**: a failed `check_cmd` produces a recorded triage — reproduce, localize, one evidence-cited root-cause hypothesis — before either a fix attempt or `blocked`; any fix carries a regression test that failed first; and the policy states that output read from tools, errors, or external models is untrusted data.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. The triage SHALL be performed by a fresh context that never sees the builder's reasoning.
   - Given a failed `check_cmd`, when triage runs, then it is delegated to a subagent whose payload is the spec, the failure output, and the diff — and NOT the builder's reasoning, plan, or prior attempts. Same blind protocol as review, applied to diagnosis.
   - Given the triage result, when the builder acts on it, then it receives the hypothesis and its evidence, not a directive.
2. The triage SHALL precede the second attempt, not merely precede `blocked`.
   - Given a first `check_cmd` failure, when the stage makes any further change, then a triage record already exists in the spec's Notes and is timestamped or ordered before that change — a triage appended after two blind attempts, immediately prior to `blocked`, does NOT satisfy this.
3. A triage record SHALL contain all three parts or it is not a triage.
   - Given a triage record, when it is checked, then it contains a reproduce step, a localization to file or symbol, and a single root-cause hypothesis with cited evidence; and given a record missing any part, then it is rejected and the spec cannot advance to `blocked` as triaged.
4. The triage SHALL be bounded and SHALL NOT increase the retry budget.
   - Given repeated failures, when triage completes, then the total attempts consumed match today's bound, and no configuration makes triage unbounded.
5. A fix that follows triage SHALL carry a regression test targeting the hypothesized root cause specifically, distinct from the spec's own `check_cmd`.
   - Given a triage naming a root cause, when the fix is applied, then a test exists that exercises that root cause, fails against the pre-fix tree, and passes after — satisfying the spec's top-level `check_cmd` alone does not discharge this.
6. The policy SHALL state that tool, error, and external-model output is data, never instructions.
   - Given `templates/LOOP_POLICY.md`, when read, then it contains one rule covering all three sources; and given a fixture whose error text contains an embedded instruction such as a command to run or a URL to fetch, when a stage processes it, then the instruction is not followed and the attempt is recorded.
7. The reviewer's finding class for acted-upon untrusted output SHALL fire unconditionally, not behind the `guards` flag.
   - Given a diff that executes or fetches something sourced from an error message or an external model's response, when the blind review runs with `guards` disabled, then it is still reported as a finding with evidence — this is a security class, and the flag-gated checklist is for quality sweeps.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite triage
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Every acceptance criterion needs its own `kind: bash-unit` case. Sketches: 1 asserts the
triage payload excludes builder reasoning (a fixture payload containing it must
fail the case); 2 and 3 drive the triage check over fixture Notes files
(well-formed, missing-a-part, appended-too-late); 4 asserts the attempt counter
against today's bound; 5 uses a fixture pair where the top-level check passes
but no root-cause test exists; 6 is the embedded-instruction error string; 7
runs the reviewer prompt with `guards` explicitly false. Mutation-test each.

## Notes / decisions (append-only)

- Folding the surviving half of §2.3.2 in here rather than giving it its own
  spec: the shell-injection concern was checked and does not apply to our shims,
  and what remains — external model output is untrusted — is the same rule as
  untrusted tool output. One rule stated once beats the same rule stated twice in
  two places that can drift apart.
- Blind triage (acceptance 1, owner ruling 2026-08-04). The draft left this
  unstated, which defaulted it to the builder diagnosing itself — the exact
  anchoring the blind-review protocol exists to defeat, and worse here than in
  review, because a confidently wrong root cause doesn't just get reported, it
  steers the remaining attempt. Costs one cheap-tier spawn per failure.
- Triage informing rather than extending the retry budget (acceptance 4) is the
  other hard call. The alternative — diagnose, then get another attempt — is how a
  bounded loop becomes an unbounded one, and this repo has already paid for that
  lesson once.

- **Two acceptances remain partly prose, and that is recorded rather than
  hidden.** Acceptance 1 is now mechanical — `triage.sh payload` constructs the
  blind payload in one place and case 412 proves builder reasoning cannot leak
  into it — but nothing forces the build stage to USE it; that is SKILL.md
  prose. Acceptance 5's regression-test requirement is prose only: no check can
  tell a root-cause test from any other passing test. And acceptance 3's "cannot
  advance to blocked as triaged" is not wired into `tracker.sh` — the validator
  exists and the stage is told to run it. Making these mechanical needs a
  tracker-side hook, which is a bigger change than this spec's boundaries allow.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 3, absorbing §2.3.2's surviving half.
- 2026-08-02 spec-review: MODIFIED acceptance 1 — as written it only required triage to exist when the stage gave up, which a builder could satisfy with two blind attempts plus a cosmetic note appended before `blocked`, defeating the spec's purpose. Now ordered before the second attempt.
- 2026-08-02 spec-review: ADDED acceptance 2 (a triage record must contain all three parts) — completeness was implied by prose, not required.
- 2026-08-02 spec-review: MODIFIED acceptance 4 — was indistinguishable from the existing Red Gate, which already requires check_cmd to fail then pass. Now scoped to a root-cause-specific test.
- 2026-08-02 spec-review: MODIFIED acceptance 6 to fire unconditionally — the reviewer's only existing finding-class mechanism is the `guards` checklist, which is off by default, so an untrusted-output finding would have shipped disabled.
- 2026-08-02 spec-review: MODIFIED the `blocked` boundary, which contradicted acceptance 1 by claiming nothing about recording changed.
- 2026-08-02 spec-review: ADDED per-criterion fixture sketches (only one criterion had one) and `depends_on: 004`.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
- 2026-08-04 grill: ADDED acceptance 1 — triage runs in a fresh context blind to the builder's reasoning (owner ruling). Renumbered the rest, so entries above this line refer to the OLD numbering (old 1->new 2, 2->3, 3->4, 4->5, 5->6, 6->7); added the no-edit boundary and the payload-exclusion fixture.
- 2026-08-08 build: BUILT on `claude/idea-003-failure-triage`. Red Gate honoured: 11 cases first, 10 genuine failures, then implemented.
- 2026-08-08 review: FIXED case 408, which checked keyword proximity rather than structural placement. The reviewer moved the whole untrusted-output paragraph INSIDE the guards-gated section and all 11 cases still passed — the exact mutation acceptance 7 exists to prevent. Now asserts line position relative to the guards gate.
- 2026-08-08 review: ADDED case 411 and a fixture. The `hypothesis:` check had zero coverage; neutering it left every case green.
- 2026-08-08 review: ADDED `triage.sh payload` and case 412, implementing this spec's own build-order sketch for acceptance 1 rather than leaving it as prose.
- 2026-08-08 review: NARROWED the scan pattern. A bare `https?://` flagged routine npm/pip fetch errors as embedded instructions, which trains people to ignore the warning. A URL now needs an imperative before it. Case 413 pins both directions.
