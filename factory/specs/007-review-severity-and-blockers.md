---
id: 007
title: Add merge-blocking severity and a bounded presumptive-blocker list to review
status: shelved
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
shelved_from: specd
shelved_reason: deferred to an attended session: its check_cmd carries --live, which spawns real claude -p calls on every build-loop re-run. Not a dependency for anything; restore with tracker.sh restore when you want to watch the quota.
shelved_at: 2026-08-09T00:30:06Z
---

# Spec 007 — Add merge-blocking severity and a bounded presumptive-blocker list to review

## Brief (the delegation contract)

- **objective**: make review findings say whether they block a merge, and give the reviewer a short fixed list of structural problems it must surface even when unasked.
- **user_intent_verbatim**: `docs/osmani-audit.md` §2.3.3 — stolen from `code-review-and-quality`. Our reviewer types findings by layer and severity but never says which ones block, and §1.3(d) found nothing in the pipeline defends legibility.
- **input_paths**: `agents/reviewer.md`, `skills/review/SKILL.md`, `docs/osmani-audit.md`, `evals/cases/review-severity/`
- **boundaries_non_goals**:
  - Does NOT widen the reviewer's remit to style or taste. `agents/reviewer.md:25` stays exactly as written; the blocker list is finite precisely so it cannot expand into general commentary.
  - Does NOT add a new revision round. Blocking findings route through the existing bounded revision, hard cap 2.
  - Does NOT let the reviewer merge or refuse to merge. It labels; the human still decides.
  - Does NOT replace or change the existing `layer: spec|test|impl` typing or the existing `severity: high|medium|low` field. Blocking is a third, independent axis; nothing about the envelope's current fields changes, so existing evals that assert on them keep passing.
- **output_spec**: every finding carries an explicit merge-blocking verdict; the PR body groups blocking findings separately; and the reviewer sweeps a declared, closed list of structural blockers on every review.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. Every finding SHALL carry an explicit blocking verdict, judged independently of `severity`.
   - Given any review output, when a finding is emitted, then it states blocking or non-blocking; a finding with no verdict is invalid.
   - Given a finding, when blocking is decided, then it is NOT derived from `severity` by any fixed mapping. The two answer different questions: `severity` is how bad the defect is, blocking is whether it should stop a merge.
   - Both directions must be expressible, and each needs a fixture: a low-severity blocking finding (a one-line silent fallback on an auth path) and a high-severity non-blocking one (a real inefficiency in a script that runs nightly). A rule that forbids either combination is a failure.
2. The PR body SHALL separate blocking findings from the rest, and the instruction SHALL be mechanically verifiable.
   - Given a review producing at least one blocking finding, when the PR is opened, then the body lists blocking findings in their own section above the others, so the evening reviewer sees them without reading the whole body.
   - No eval kind exercises a `SKILL.md`, so this acceptance is NOT satisfied by editing prose. A `bash-unit` case SHALL assert that `skills/review/SKILL.md` contains the blocking-section instruction, and SHALL fail when it is absent. A deliverable no check can fail on is not a deliverable.
3. The presumptive-blocker list SHALL be exactly these four, held in one declared place.
   1. **Complexity relocated, not reduced** — a refactor that moves difficulty elsewhere and calls it simplification.
   2. **Silent fallbacks** — a default or catch that hides a failure instead of surfacing it.
   3. **Near-duplicate helpers** — a new function doing substantially what an existing one already does.
   4. **Feature logic in shared modules** — spec-specific behavior landing in a module everything imports.
   - Given the reviewer, when it sweeps, then it checks these four and only these four; and given a candidate structural problem outside the list, then it is not reported under this mechanism.
   - Osmani's original list carries a fifth, "oversized file with no decomposition". It is deliberately excluded: file size is the most taste-adjacent of the five and the least tied to a concrete failure, and a closed list is only safe while every entry earns its place.
4. The sweep SHALL run on every review, not behind the `guards` flag.
   - Given a review with `guards` disabled, when it runs, then the presumptive-blocker sweep still happens — `guards` gates the AI-slop quality checklist, and these are structural correctness classes.
   - The mutation test for this needs `guards: false` visible to the agent, and the `headless-agent` sandbox is a bare `mktemp -d` with no `.agentic/config.json`. Seeding that config into the sandbox is part of this spec's work, not an assumption about the harness.
5. A presumptive blocker SHALL be reported as a proposal, escalating to blocking only when it makes things actively worse.
   - Given a diff that relocates complexity rather than reducing it, when the review runs, then it is surfaced with a proposed alternative and marked non-blocking; and given the same pattern where the change measurably worsens the property it claims to improve, then it is marked blocking.
6. The evidence bar SHALL be unchanged.
   - Given any presumptive-blocker finding, when reported, then it cites file:line before stating a verdict, and an empty sweep result is a valid outcome.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite review-severity --live
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

**This spec is attended-only, by owner ruling (2026-08-08), and `--live` is in
the check_cmd deliberately.** Acceptances 1, 3, 4 and 6 describe what a live
reviewer emits; those are `headless-agent` cases, which `evals/run_eval.sh:89-92`
skips unless `--live` is passed — and a skipped case never fails a run. Without
the flag this spec's gate could not fail on its own primary objective. With it,
every run of this check spends subscription tokens on real agent calls, so the
spec cannot be built by an unattended loop. That is the accepted trade.

Acceptance 1's two cross-combination fixtures are what prove blocking was not
quietly derived from severity. Acceptance 2 is a `bash-unit` grep over
`skills/review/SKILL.md` and needs no agent. Acceptance 5's escalation judgment
belongs on the anchored-rubric path. Mutation-test acceptance 4 with `guards:
false` seeded into the sandbox, confirming the case still requires the sweep.

## Notes / decisions (append-only)

- The list being *closed* (acceptance 3) is what makes this safe to add to a
  reviewer we deliberately scoped away from taste. An open-ended "surface
  structural problems" instruction is exactly the reviewer-will-always-find-
  something failure `agents/reviewer.md:25-27` warns about; a finite list cannot
  drift into style commentary. The four were chosen by the owner on 2026-08-04;
  adding a fifth is a spec change, not a reviewer's discretion.
- Independent blocking (acceptance 1, owner ruling 2026-08-04). Deriving it from
  severity was the cheaper option and was rejected because it overloads a field
  that already means something: a reviewer wanting to block a low-severity
  finding would have to inflate its severity to do so, corrupting the signal the
  envelope already carries.
- Acceptance 5's proposal-not-blocker default keeps this from becoming a merge
  bottleneck. The point is to make legibility problems visible to the human, not
  to have a reviewer veto work on structural taste.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.3.3.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
- 2026-08-04 grill: ADDED the four presumptive blockers by name (owner selection). The draft required a closed enumerated list and then never enumerated it, leaving the contents in docs/osmani-audit.md, which was not in input_paths — now added. Osmani's fifth entry (oversized file) deliberately excluded.
- 2026-08-04 grill: MODIFIED acceptance 1 — blocking is judged independently of `severity`, never derived from it (owner ruling). Added the two cross-combination fixtures that prove it, and stated that the existing envelope fields are untouched.

- 2026-08-08 spec-review: MODIFIED check_cmd to include `--live` (owner ruling). Acceptances 1/3/4/6 describe live reviewer output, and headless-agent cases skip without the flag (`evals/run_eval.sh:89-92`), so the gate could never fail on the spec's own objective. This spec is now attended-only.
- 2026-08-08 spec-review: MODIFIED acceptance 2 — the PR-body instruction lives in `skills/review/SKILL.md`, which no eval kind exercises. Now requires a bash-unit assertion that the instruction is present.
- 2026-08-08 spec-review: MODIFIED acceptance 4 — seeding `.agentic/config.json` into the headless-agent sandbox is part of the work; the sandbox is a bare mktemp with no config for the agent to read.
