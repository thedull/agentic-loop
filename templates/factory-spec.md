---
id: NNN
title: <short imperative title>
status: queued
profile: standard
created: YYYY-MM-DD
depends_on: <optional: space-separated spec ids, e.g. 003 005 — omit when independent>
claimed_by:
branch:
pr:
---

# Spec NNN — <title>

One spec file per idea. Nothing else — no constitution, research, data-model,
or contracts files (that ceremony is where spec-driven development burns
tokens without buying correctness). Downstream stages judge done-ness by
running `check_cmd`, not by re-reading prose.

## Brief (the delegation contract)

- **objective**: <one imperative sentence — if it needs "and also", split into two specs>
- **user_intent_verbatim**: <the user's original words, uncompressed>
- **input_paths**: <the seams: files/modules this change touches; ideally one. Paths only — no line numbers>
- **boundaries_non_goals**:
  - <explicit non-goal>
  - <explicit non-goal>
- **output_spec**: <what exists when this is done, stated behaviorally>
- **effort_budget**: <trivial | small | medium | large — set during triage, drives grilling depth and tier routing>

## Acceptance (behavioral, testable — no implementation details)

Each requirement is an RFC-2119 SHALL with a Given/When/Then scenario written
to be one step away from an executable test.

1. The <component> SHALL <behavior>.
   - Given <state>, when <action>, then <observable outcome>.
2. ...

## Check command (the Red Gate contract)

```
check_cmd: <single command whose exit status decides done-ness, e.g. "npm test -- --grep spec-NNN">
```

The build stage MUST run this and see it FAIL before writing implementation
code (a check that passes on an empty implementation is checking nothing),
and see it PASS before advancing to `built`.

## Notes / decisions (append-only)

<!-- If this spec is classified irreversible (`tracker.sh irreversible <file>`
     exits 7) it cannot reach `specd` whole — split it with
     `tracker.sh split <file>`. To override, add an explicit line here:
     - **irreversible-override**: <your name> — <why this is safe>
     Silence is never consent; the classifier never asks. -->

<!-- `profile:` is the CONSEQUENCE switch; `effort_budget` is size. The two are
     orthogonal and neither derives the other. Values: standard | hardened |
     dark. Resolve with `scripts/lib/tracker.sh profile <file>`.
     - unknown value  -> the spec is refused rather than defaulting
     - dark           -> refused until the dark lane exists (spec 015)
     - hardened       -> refused unless spec 005's payload marker
                         `profile-hardened-payload:` is present under agents/,
                         so a hardened spec can never be quietly given a
                         standard review
     Casing and surrounding whitespace are normalised; anything trailing the
     value (including a comment) is refused — keep this field bare. -->

- <ADR-style note ONLY when a decision is hard to reverse, surprising without
  context, AND the result of a real trade-off — 1–3 sentences>

## Revision log (deltas only — never regenerate this spec)

- <date> <stage>: ADDED/MODIFIED/REMOVED <what and why, one line each>
