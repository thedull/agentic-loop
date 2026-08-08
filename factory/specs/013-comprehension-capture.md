---
id: 013
title: Capture diff size and review-finding count in the event log
status: queued
profile: standard
created: 2026-08-04
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 013 — Capture diff size and review-finding count in the event log

## Brief (the delegation contract)

- **objective**: add the two fields the comprehension proxies need — how much code a spec shipped, and how much the reviewer had to say about it.
- **user_intent_verbatim**: split out of spec 011 during grilling (owner ruling 2026-08-04). The review gate proved spec 011's load-bearing claim false: it asserted all four proxies come from data already captured, and grepping every `obs_event` call site showed diff size and findings count are captured nowhere. `obs_shim_tap` records `detail.artifacts` and `detail.caveats_count` only.
- **input_paths**: `scripts/lib/obs.sh`, `scripts/observe.sh`, `skills/review/SKILL.md`, `docs/observability.md`, `evals/cases/comprehension-capture/`
- **boundaries_non_goals**:
  - Does NOT compute or report any metric. That is spec 011, which depends on this.
  - Does NOT bump the envelope version. Both fields go under `detail`, and consumers read with `// null` fallbacks, matching how `phase`/`spec_id` were added.
  - Does NOT capture the diff itself, only its size. The event log is a log, not a mirror of the repository.
  - Does NOT change any existing field's meaning or any existing event type.
- **output_spec**: a spec that reaches `pr-open` has, in its event stream, the size of the diff it produced and the number of findings its blind review raised — both null when genuinely unknown, never zero-as-a-guess.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. Diff size SHALL be captured at the point a diff exists.
   - Given a spec reaching the review stage, when the event is emitted, then it carries the diff's size in lines added and removed against the branch point; and given no branch or no diff, then both are null.
2. Review-finding count SHALL be captured from the reviewer's own envelope.
   - Given a completed blind review, when the event is emitted, then it carries the count of findings the reviewer returned; and given a review that did not complete, then the count is null — not zero, which would be indistinguishable from a clean review.
3. Nulls SHALL be honest, per the existing rule.
   - Given any case where a value cannot be determined, when the event is emitted, then the field is null and no fallback value is substituted — `scripts/lib/obs.sh` already forbids fabricating what a source did not report, and this spec adds no exception.
4. The envelope version SHALL NOT change.
   - Given these two new fields, when an older consumer reads the event, then it continues to work via `// null` fallbacks, exactly as it did when `phase` and `spec_id` were added.
5. Existing events SHALL be unaffected.
   - Given the existing observability suite, when it runs before and after this change, then all 22 cases still pass and no existing field's value changes.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite comprehension-capture
```

**Build order (spec 004 acceptance 7).** New suite of its own; a missing suite
exits 4 and is not a valid red. Write the suite and its cases first, see them
genuinely fail, then implement.

Fixtures: a review with findings, a clean review (count 0, meaningfully distinct
from null), an aborted review (null), and a spec with no branch (null diff
size). Acceptance 3 is the one to mutation-test — a capture that substitutes 0
for null passes a naive presence check while destroying the distinction the
whole metric family rests on.

## Notes / decisions (append-only)

- Split from spec 011 (owner ruling 2026-08-04) rather than widening 011 to
  include capture. 011's boundary forbade touching capture for a good reason:
  the capture plane is the component the architecture says must never break the
  loop, and a metrics spec is the wrong seam to be editing it from.
- Zero versus null (acceptance 2) is the distinction that makes the findings
  proxy worth anything. A clean review and a review that never ran are opposite
  signals about a spec, and collapsing them into 0 would make review-finding
  density silently meaningless in exactly the cases most worth noticing.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-04 spec: ADDED, split out of spec 011 after the review gate disproved 011's claim that all four proxies were already captured.
