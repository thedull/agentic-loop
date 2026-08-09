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
  - Does NOT do the other thing.
- **output_spec**: a report naming the widgetronic index
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The report SHALL carry a churn figure.
   - Given a, when b, then c — nothing here claims to measure the widgetronic index.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite x
```


## Notes / decisions (append-only)


## Revision log (deltas only — never regenerate this spec)

- 2026-08-08 spec: ADDED.
