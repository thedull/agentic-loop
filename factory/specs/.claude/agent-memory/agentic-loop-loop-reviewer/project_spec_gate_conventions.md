---
name: project-spec-gate-conventions
description: Established conventions in this repo's factory/specs/*.md pipeline that a spec-review pass should NOT flag as bugs
metadata:
  type: project
---

This repo (agentic-loop plugin) runs a spec-review gate over `factory/specs/NNN-*.md`
files before build. Two conventions are intentional, not defects:

1. **Per-spec eval suite + depends_on: 004.** Spec 004
   (`factory/specs/004-eval-runner-zero-case-exit.md`) fixes `evals/run_eval.sh`
   so it exits non-zero on zero-matched cases. Until 004 lands, every downstream
   spec's `check_cmd: ./evals/run_eval.sh --suite <new-suite>` will exit 0 with
   "0 pass, 0 fail, 0 skipped" because the suite directory doesn't exist yet —
   confirmed by running it (e.g. `--suite hardened`, `--suite grill-stop` both
   printed "0 pass, 0 fail, 0 skipped" / exit 0 as of 2026-08-02). This is
   expected and each downstream spec correctly declares `depends_on: 004`.
   Do not report this as a "vacuous check_cmd" finding — it's the documented,
   intended bootstrapping order (see spec 004's Notes and spec 001's Revision log).
2. **New suite per spec, never an existing one.** Established by spec 004's
   Notes and followed by specs 001, 002, 005, 006: sharing an existing suite
   (e.g. `tracker`, `observability`) would make the check_cmd pass before any
   work exists. Verify the named suite directory under `evals/cases/<name>/`
   does not yet exist — if it does, that's a real vacuous-check_cmd finding.

See [[feedback-input-paths-scope-omission]] for a recurring defect class to
watch across future specs.
