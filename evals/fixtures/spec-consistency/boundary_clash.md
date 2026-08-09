---
id: 800
title: fixture
status: queued
profile: standard
created: 2026-08-08
depends_on:
claimed_by:
branch:
pr:
---

# Spec 800 — fixture

## Brief (the delegation contract)

- **objective**: do the thing
- **input_paths**: `scripts/lib/a.sh`, `evals/cases/x/`
- **boundaries_non_goals**:
  - Does NOT rewrite the manifest.
- **output_spec**: a thing
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The tool SHALL rewrite the manifest in place.
   - Given a, when b, then c.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite x
```


## Notes / decisions (append-only)


## Revision log (deltas only — never regenerate this spec)

- 2026-08-08 spec: ADDED.
