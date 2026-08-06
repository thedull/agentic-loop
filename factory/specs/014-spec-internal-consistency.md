---
id: 014
title: Check a spec against itself before it reaches specd
status: queued
profile: standard
created: 2026-08-04
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 014 — Check a spec against itself before it reaches specd

## Brief (the delegation contract)

- **objective**: catch a spec whose Brief and acceptance criteria have drifted apart — blocking on what a script can decide, and narrowing what a reviewer must read for the rest.
- **user_intent_verbatim**: "Yes, add it as a new spec" (2026-08-04), after spec 011 reached a pushed commit with an `output_spec` naming a metric its acceptances had renamed, and an `objective` asserting a claim the review gate had already disproved. Its acceptances were corrected three times during grilling and the Brief above them was never re-read.
- **input_paths**: `skills/spec/SKILL.md`, `templates/factory-spec.md`, `scripts/lib/`, `evals/cases/spec-consistency/`, `evals/fixtures/`
- **boundaries_non_goals**:
  - Does NOT judge whether a spec is *good*. It checks a spec against itself, never against intent.
  - Does NOT put an LLM inside a gate. Two checks block because they are decidable; two produce candidates for the existing blind spec-review to adjudicate. See the routing rule in Notes.
  - Does NOT rewrite specs. It reports; the author fixes.
  - Does NOT run during build or review. This is a spec-stage check, and its value is entirely in running before `specd`.
  - Does NOT change what the spec-review reviewer looks for. It adds candidates to the reviewer's payload; the reviewer's own full-spec sweep is unchanged and still authoritative.
- **output_spec**: a command that reads one spec file and reports four classes of internal inconsistency — exiting non-zero on the two decidable ones, and listing the other two as candidates without affecting exit status.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

### Blocking checks (decidable by a script)

1. An acceptance naming a path absent from `input_paths` SHALL block.
   - Given an acceptance criterion naming a file path not listed in `input_paths`, when the check runs, then it reports the omission and exits non-zero.
   - Given a path named only in the Notes, Revision log, or Check-command sections, when the check runs, then it is NOT treated as an acceptance reference — fixture provenance is not scope, and a spec may cite history without widening its seams.
   - The reverse direction — an `input_paths` entry no acceptance names — is deliberately NOT checked. See Notes: requiring it would contradict the template.
2. Stale acceptance references SHALL be detected and SHALL block.
   - Given a Notes or Revision-log entry citing an acceptance number greater than the count of acceptances present, when the check runs, then it reports it and exits non-zero.

### Candidate checks (narrow the reading, never decide it)

3. Vocabulary drift SHALL be surfaced as candidates, not adjudicated.
   - Given a distinctive term in `output_spec` that appears in no acceptance criterion, when the check runs, then it is listed as a candidate and exit status is unaffected.
   - Given the term appearing anywhere in the acceptances — including in unrelated prose — when the check runs, then no candidate is raised for it, and this SHALL be treated as a known miss rather than a bug. See Notes.
4. Boundary candidates SHALL be surfaced without being adjudicated.
   - Given a `Does NOT <X>` boundary whose distinctive terms also appear in an acceptance criterion, when the check runs, then it is listed as a candidate and exit status is unaffected.
   - Given an acceptance that restates a boundary in agreement with it, when the check runs, then it is still listed — narrowing what a human reads is the goal, not being right.

### Wiring

5. Candidates SHALL reach the spec-review reviewer, and this SHALL be a declared change to its payload.
   - Given candidates from checks 3 and 4, when the spec-review gate runs, then they are appended to the reviewer's payload alongside the spec file path.
   - `skills/spec/SKILL.md` today specifies the reviewer receives "ONLY the spec file path (blind, fresh context)". This spec amends that to "the spec file path and the candidate list", and the amendment is part of the work rather than an undeclared side effect. Blindness is preserved: candidates are derived from the spec itself, never from the author's reasoning.
6. Blocking failures SHALL prevent `specd`, and SHALL run before the reviewer is spent.
   - Given a spec failing check 1 or 2, when the spec stage runs, then it does not advance to `specd`, and the spec-review gate is not invoked on a spec that contradicts itself.
7. The check SHALL be usable on any spec file, standalone.
   - Given a spec file path, when the check is invoked directly, then it runs — no tracker state, no claim, no branch.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite spec-consistency
```

**Build order (spec 004 acceptance 7).** New suite of its own; a missing suite
exits 4 and is not a valid red. Write the suite and its cases first, see them
genuinely fail, then implement.

Fixtures are copies of this session's real defects, placed under
`evals/fixtures/` so the suite has no dependency on git history or on the live
`factory/specs/` tree:

| Fixture | From | Asserts |
|---|---|---|
| drift | spec 011 at `d9c6b3a` | check 3 raises **no** candidate — the known miss of acceptance 3, pinned as a test so the limitation cannot be forgotten |
| path-missing | spec 007 before `9878244` | check 1 direction 1 blocks |
| stale-number | spec 003 after renumbering | check 2 blocks |
| boundary | spec 003 at `5760e8b` | check 4 raises a candidate, exit status unaffected |
| clean | a minimal valid spec | everything passes, no candidates |

Mutation-test checks 3 and 4 in the unusual direction: make them affect exit
status and confirm a case fails. The danger in this spec is not a missed
defect — it is the check quietly promoting itself from reporter to judge.

## Notes / decisions (append-only)

- **The routing rule, which is the whole design.** A gate refuses on decidable
  facts; a reviewer judges. Checks 1 and 2 are set operations over paths and
  integers, so they block. Checks 3 and 4 require reading, so the script narrows
  the candidate set and the blind spec-review adjudicates — an LLM acting as a
  reviewer, which this repo already relies on, rather than as a gate, which it
  refuses. Consistent with spec 002's two-state ruling instead of quietly
  reversing it.
- **Vocabulary drift is a candidate, not a gate — and the reason is recorded as
  a fixture** (owner ruling 2026-08-04, off a review-gate finding). The defect
  that prompted this whole spec is not catchable by term matching: at `d9c6b3a`
  spec 011's `output_spec` said "re-open rate" while its acceptances said "build
  churn", but the word "re-open" *did* appear in acceptance 5's disclaimer
  prose. A presence check finds it and stays silent. Deciding it properly means
  knowing that `output_spec` names something *as a reported field* and no
  acceptance does — that is reading, not matching. The alternative considered
  and set aside was restructuring `output_spec` into an enumerated list in
  `templates/factory-spec.md`, which would make drift decidable at the cost of a
  template migration for every spec already written.
  The `drift` fixture asserts the miss rather than hiding it, so nobody later
  mistakes the check for complete.
- **The reverse direction was specified, then removed, and the removal is the
  more useful result.** An earlier revision required every `input_paths` entry to
  be named by some acceptance. Applying that to this spec failed it on four of
  five entries, which was the clue: `templates/factory-spec.md:31` says
  acceptances are "behavioral, testable — no implementation details", while
  `input_paths` at `:24` is "the seams: files/modules this change touches". The
  check would have forced implementation paths into acceptance criteria — pushing
  every future spec to violate the template in order to pass a gate meant to
  enforce it. Direction 1 stands because it is the opposite case: an acceptance
  that *does* name a path is asserting scope, and that scope must be declared.
- Deliberately not checked: whether the acceptances cover the `objective`. That
  is completeness, it needs judgment, and the spec-review gate already asks it.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-04 spec: ADDED at the owner's request, after spec 011 reached a pushed commit with its Brief contradicting its own acceptances. Scope selected by the owner: vocabulary drift, input_paths coverage, stale acceptance numbers, boundary candidates.
- 2026-08-04 spec-review: MODIFIED — the gate applied this spec's checks to this spec and found it failing its own `input_paths` coverage (fixtures cited spec files absent from `input_paths`). Fixtures now live under `evals/fixtures/`, which is declared.
- 2026-08-04 spec-review: MODIFIED — vocabulary drift demoted from blocking to candidate (owner ruling). The gate proved the canonical fixture is not catchable by term matching, because the drifted term reappeared in unrelated prose. The miss is now pinned as a fixture.
- 2026-08-04 spec-review: MODIFIED check 1 direction 2 to state its exit status explicitly; it previously said only "reports it", which was exactly the ambiguity class this spec detects.
- 2026-08-04 spec-review: ADDED acceptance 5 — the candidate list changes the reviewer's documented "ONLY the spec file path" contract, which the draft required without declaring. Now an explicit amendment with blindness preserved, plus a boundary stating the reviewer's own sweep is unchanged.
- 2026-08-04 self-check: REMOVED check 1's reverse direction. Running the spec's own check against the spec failed it on 4 of 5 input_paths, which exposed that the direction contradicts `templates/factory-spec.md:31` — it would force implementation paths into acceptance criteria, which the template forbids. Direction 1 retained.
