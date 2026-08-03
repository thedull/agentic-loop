---
id: 006
title: Replace the grilling question cap with a predictive stop condition
status: queued
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 006 — Replace the grilling question cap with a predictive stop condition

## Brief (the delegation contract)

- **objective**: stop grilling when the interviewer can predict the user's answers, not when an arbitrary counter runs out.
- **user_intent_verbatim**: `docs/osmani-audit.md` §2.3.1 — stolen from `interview-me`. Our cap of roughly five questions is simultaneously too many for an obvious idea and too few for a genuinely ambiguous one.
- **input_paths**: `skills/spec/SKILL.md`, `evals/cases/grill-stop/`
- **boundaries_non_goals**:
  - Does NOT remove the ceiling. The count survives as a runaway backstop; it stops being the primary stop condition.
  - Does NOT change the one-question-at-a-time protocol, or the rule that the agent greps the codebase rather than asking what it can read.
  - Does NOT change `grill` / `grill deep` flag semantics beyond what the stop condition implies.
  - Does NOT apply to unattended stages. Grilling is interactive by definition.
- **output_spec**: the spec skill continues asking while it cannot predict the user's answer to the next question it would ask, stops when it can, and records which condition ended the interview.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The interview SHALL stop when the interviewer can predict the answers to the next questions it would ask.
   - Given an interview where the remaining unknowns are predictable from what the user has already said, when the interviewer evaluates the stop condition, then it stops and states that it stopped on prediction.
2. The interview SHALL continue past the old count when unknowns remain unpredictable.
   - Given an ambiguous idea where the sixth question would still change the spec, when the interviewer evaluates the stop condition, then it asks it — the former cap does not end the interview.
3. A ceiling SHALL remain, and hitting it SHALL be recorded as a distinct, visible outcome.
   - Given an interview that reaches the ceiling without the predictive condition being met, when it ends, then it stops and records "stopped on ceiling, unknowns remain" — never presented as a satisfied interview.
4. The terminating condition SHALL be written to the spec.
   - Given any completed interview, when the spec is emitted, then the spec records which of the two conditions ended it, so a later reader can tell a confident spec from a truncated one.
5. Non-answers SHALL NOT satisfy the stop condition.
   - Given a user reply of "whatever you think" or "sounds good", when the interviewer evaluates it, then that question is treated as unanswered and re-asked with concrete options, rather than counted as resolved.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite grill-stop
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Acceptances 3, 4 and 5 are mechanically checkable over fixture transcripts and
emitted specs. Acceptances 1 and 2 are judgment and belong on the
anchored-rubric or `--live` path — they must not be asserted by a judge
pretending to be a unit test.

## Notes / decisions (append-only)

- Acceptance 3 exists because replacing a cap with a judgment call invites the
  judgment to be optimistic. Recording ceiling-termination as a distinct outcome
  keeps a truncated interview visibly truncated instead of laundering it into a
  finished one — the same reason spec 005 refuses silent omission.
- Acceptance 5 is the cheapest of the five and probably the highest value: the
  most common real-world failure is not too few questions but a question
  answered with delegation and scored as answered.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.3.1.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
