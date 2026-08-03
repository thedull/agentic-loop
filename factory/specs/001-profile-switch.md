---
id: 001
title: Wire profile as a three-position consequence switch
status: queued
profile: standard
created: 2026-08-02
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 001 — Wire profile as a three-position consequence switch

## Brief (the delegation contract)

- **objective**: make the spec frontmatter `profile:` field route real behavior instead of being inert metadata.
- **user_intent_verbatim**: "start creating specs out from osmani-audit doc" — this is backlog item 1 of `docs/osmani-audit.md` §2.7, which closes findings §1.3(a) "we have no switch" and §1.3(b) "effort_budget measures size, not stakes".
- **input_paths**: `templates/factory-spec.md`, `skills/spec/SKILL.md`, `skills/review/SKILL.md`, `scripts/lib/tracker.sh`, `evals/cases/spec-gate/`
- **boundaries_non_goals**:
  - Does NOT implement the irreversibility classifier that decides which profile a spec gets — that is spec 002. This spec makes the field *mean* something; 002 makes it get *set* automatically.
  - Does NOT implement the `hardened` security review payload — that is spec 004. Here `hardened` routes to a documented placeholder that fails loudly if unimplemented, never silently behaving as `standard`.
  - Does NOT implement any dark-lane behavior. `profile: dark` is REJECTED by this spec, not honored.
  - Does NOT touch `effort_budget`, which keeps meaning size.
- **output_spec**: `profile:` accepts exactly `standard | hardened | dark`; an unrecognized value blocks the spec rather than defaulting; `standard` behaves exactly as today; `hardened` additionally routes through the deeper review path; `dark` is refused with a message naming spec 011 as its prerequisite.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The spec tooling SHALL accept only `standard`, `hardened`, or `dark` as a `profile:` value.
   - Given a spec file with `profile: banana`, when a stage reads it, then the stage refuses and marks the spec `blocked` with a message naming the three valid values.
2. The tooling SHALL treat a missing or empty `profile:` as `standard`.
   - Given a spec file with no `profile:` line, when a stage reads it, then behavior is identical to `profile: standard` and no warning is emitted.
3. The review stage SHALL route `hardened` specs through the deeper review path and SHALL NOT silently fall back to the standard path.
   - Given a spec with `profile: hardened`, when the review stage runs and the deep security payload of spec 004 is not yet present, then the stage refuses with an explicit "hardened profile requested but the hardened review payload is not installed (see spec 004)" message rather than reviewing it as `standard`.
4. The tooling SHALL refuse `profile: dark` until the dark lane exists.
   - Given a spec with `profile: dark`, when any stage claims it, then the stage refuses with a message naming spec 011, and the spec is left in its current status rather than advanced.
5. `profile` SHALL be orthogonal to `effort_budget`, and neither SHALL be derived from the other.
   - Given a spec with `effort_budget: trivial` and `profile: hardened`, when the review stage runs, then the hardened path is used — smallness does not downgrade consequence.
6. Value matching SHALL be exact after trimming surrounding whitespace, and SHALL NOT be case-insensitive or comment-tolerant.
   - Given `profile: Standard`, `profile: standard # note`, or `profile:standard`, when a stage reads it, then each is refused per acceptance 1 rather than silently accepted; and given `profile:  standard  ` with padding, then it is accepted as `standard`.
7. The `hardened` presence check SHALL be a positive test for the payload, not an assumption.
   - Given the review stage encountering `profile: hardened`, when it decides whether the hardened path is installed, then it tests for a named marker that spec 004's payload provides, and the absence of that marker triggers acceptance 3's refusal.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite spec-gate
```

The build stage MUST run this and see it FAIL before writing implementation
code, and see it PASS before advancing to `built`.

**This check_cmd is only meaningful once spec 004 lands** — the spec-review gate
verified that today `--suite spec-gate` exits 0 on the untouched tree, because
its one case is `--live`-only and skips, and a run that executes nothing reports
success. Hence `depends_on: 004`. Every case this spec adds must be
`kind: bash-unit` so it runs free and actually executes; each guard is
mutation-tested — remove the guard, confirm the case fails.

## Notes / decisions (append-only)

- Fail-loud over fail-silent on `hardened` (acceptance 3) is the whole point of
  the field. A `hardened` spec that quietly gets a standard review is worse than
  no field at all, because it manufactures false assurance — the exact failure
  class `docs/osmani-audit.md` §1.3(a) names.
- `dark` is defined in the enum now rather than added later so that the value
  space is stable from the start and a future spec 011 changes behavior, not
  vocabulary. Refusing it explicitly also means a hand-written `profile: dark`
  can never be silently honored by a partially-built lane.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 1.
- 2026-08-02 spec-review: ADDED `depends_on: 004` and the check_cmd caveat — the gate ran the proposed check_cmd and found it exits 0 untouched (vacuous). Root cause is the runner, not this spec.
- 2026-08-02 spec-review: ADDED acceptance 6 (value normalization — case, whitespace, trailing comments were unspecified and two implementers would diverge).
- 2026-08-02 spec-review: ADDED acceptance 7 (the `hardened` presence check must be a positive marker test, previously implied only by the Brief's boundaries).
