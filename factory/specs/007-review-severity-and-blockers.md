---
id: 007
title: Add merge-blocking severity and a bounded presumptive-blocker list to review
status: queued
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 007 — Add merge-blocking severity and a bounded presumptive-blocker list to review

## Brief (the delegation contract)

- **objective**: make review findings say whether they block a merge, and give the reviewer a short fixed list of structural problems it must surface even when unasked.
- **user_intent_verbatim**: `docs/osmani-audit.md` §2.3.3 — stolen from `code-review-and-quality`. Our reviewer types findings by layer and severity but never says which ones block, and §1.3(d) found nothing in the pipeline defends legibility.
- **input_paths**: `agents/reviewer.md`, `skills/review/SKILL.md`, `evals/cases/review-severity/`
- **boundaries_non_goals**:
  - Does NOT widen the reviewer's remit to style or taste. `agents/reviewer.md:25` stays exactly as written; the blocker list is finite precisely so it cannot expand into general commentary.
  - Does NOT add a new revision round. Blocking findings route through the existing bounded revision, hard cap 2.
  - Does NOT let the reviewer merge or refuse to merge. It labels; the human still decides.
  - Does NOT replace the existing `layer: spec|test|impl` typing — severity is orthogonal to layer.
- **output_spec**: every finding carries an explicit merge-blocking verdict; the PR body groups blocking findings separately; and the reviewer sweeps a declared, closed list of structural blockers on every review.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. Every finding SHALL carry an explicit blocking verdict.
   - Given any review output, when a finding is emitted, then it states blocking or non-blocking; a finding with no verdict is invalid.
2. The PR body SHALL separate blocking findings from the rest.
   - Given a review producing at least one blocking finding, when the PR is opened, then the body lists blocking findings in their own section above the others, so the evening reviewer sees them without reading the whole body.
3. The presumptive-blocker list SHALL be closed and declared.
   - Given the reviewer, when it sweeps, then it uses a fixed enumerated list held in one place; and given a candidate structural problem not on that list, then it is not reported under this mechanism.
4. The sweep SHALL run on every review, not behind the `guards` flag.
   - Given a review with `guards` disabled, when it runs, then the presumptive-blocker sweep still happens — `guards` gates the AI-slop quality checklist, and these are structural correctness classes.
5. A presumptive blocker SHALL be reported as a proposal, escalating to blocking only when it makes things actively worse.
   - Given a diff that relocates complexity rather than reducing it, when the review runs, then it is surfaced with a proposed alternative and marked non-blocking; and given the same pattern where the change measurably worsens the property it claims to improve, then it is marked blocking.
6. The evidence bar SHALL be unchanged.
   - Given any presumptive-blocker finding, when reported, then it cites file:line before stating a verdict, and an empty sweep result is a valid outcome.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite review-severity
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Acceptances 1–4 and 6 are mechanically checkable over fixture review outputs and
PR bodies. Acceptance 5's escalation judgment belongs on the anchored-rubric
path. Mutation-test acceptance 4 with `guards: false`, confirming the case still
requires the sweep.

## Notes / decisions (append-only)

- The list being *closed* (acceptance 3) is what makes this safe to add to a
  reviewer we deliberately scoped away from taste. An open-ended "surface
  structural problems" instruction is exactly the reviewer-will-always-find-
  something failure `agents/reviewer.md:25-27` warns about; a finite list cannot
  drift into style commentary.
- Acceptance 5's proposal-not-blocker default keeps this from becoming a merge
  bottleneck. The point is to make legibility problems visible to the human, not
  to have a reviewer veto work on structural taste.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.3.3.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
