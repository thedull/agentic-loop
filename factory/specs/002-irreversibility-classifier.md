---
id: 002
title: Classify irreversible changes at spec time and force expand/contract
status: queued
profile: standard
created: 2026-08-02
depends_on: 001 004
claimed_by:
branch:
pr:
---

# Spec 002 — Classify irreversible changes at spec time and force expand/contract

## Brief (the delegation contract)

- **objective**: detect migration-shaped and otherwise irreversible specs during the spec stage, set `profile: hardened`, and require the expand/contract split before the work can be claimed.
- **user_intent_verbatim**: backlog item 2 of `docs/osmani-audit.md` §2.7 — the highest-ranked real gap, because it is the only one whose current failure mode is "ships green and breaks production".
- **input_paths**: `skills/spec/SKILL.md`, `scripts/lib/tracker.sh`, `templates/factory-spec.md`, `evals/cases/irreversible/`
- **boundaries_non_goals**:
  - Does NOT write migrations, generate DDL, or inspect a database. It classifies the *spec*, not the schema.
  - Does NOT attempt to be exhaustive. An incomplete classifier that fails closed is the deliverable; a "smart" classifier that guesses reversible is a regression.
  - Does NOT block the human from overriding — an explicit human override is allowed and recorded, but never inferred.
  - Does NOT implement the dark lane's clause 4; it only provides the classifier that clause will call (spec 012).
  - Does NOT read code, diffs, or branches. Classification happens at spec time, when no branch exists — the only inputs are the spec file's own text and paths.
- **output_spec**: the spec stage refuses to emit a `specd` spec classified irreversible unless it has been split into an expand spec and a contract spec joined by `depends_on`; both specs of the pair carry `profile: hardened`.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. The signal set SHALL live in one declared, editable list rather than scattered literals.
   - Given the classifier, when a maintainer adds a signal, then they edit one named list file and no code; and given that file is missing or empty, then the classifier refuses rather than classifying everything reversible.
2. The spec stage SHALL classify a spec as irreversible when its own text matches any signal in that list.
   - Given a spec whose `input_paths` include a path matching a migration-directory signal, or whose `objective`/`output_spec` text matches a destructive-change signal (column or table drop, rename, removal of a published interface), when the spec stage completes, then the spec is classified irreversible.
   - Inputs are limited to the spec file's own fields. No branch, diff, or database is consulted, because at classification time none exists.
3. The classifier SHALL fail closed on uncertainty.
   - Given a spec the classifier cannot confidently categorize, when it completes, then the result is "irreversible", not "reversible".
4. An irreversible spec SHALL NOT reach `specd` as a single spec.
   - Given an irreversible spec that has not been split, when the spec stage tries to advance it, then the advance is refused with a message naming the required expand/contract split, and the spec stays `queued`.
5. The split SHALL use the existing dependency machinery rather than new state.
   - Given a correctly split pair, when the tracker evaluates claimability, then the contract spec is unclaimable until the expand spec is `done`, enforced by the existing `depends_on` rule (satisfied only by `done`, never `built`/`pr-open`).
6. Both specs of a split pair SHALL carry `profile: hardened`.
   - Given a classified-irreversible spec, when it is split, then the expand spec and the contract spec each have `profile: hardened` in frontmatter without the author setting it by hand.
7. A human override SHALL be an explicit recorded artifact, never an inferred one.
   - Given a spec whose Notes contain an override line naming the overriding human and a stated reason, when the spec stage runs, then the spec proceeds as reversible and the override is preserved in the Revision log.
   - Given a spec with no such line, when the spec stage runs unattended, then no override occurs and acceptance 4's refusal stands — the classifier never asks, and silence is never consent.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite irreversible
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Every acceptance criterion needs a `kind: bash-unit` case driven by a fixture
spec file in `evals/fixtures/`. Acceptance 3 needs a fixture the classifier
genuinely cannot categorize; acceptance 7 needs two fixtures differing only by
the presence of the override line. Mutation-test each guard.

## Notes / decisions (append-only)

- Fail-closed (acceptance 2) is the hard-to-reverse decision here and it has a
  real cost: false positives will send ordinary specs through the expand/contract
  ceremony. That is the correct trade because the asymmetry is severe — a false
  positive costs one extra spec file, a false negative costs a production outage
  during rollout while every test stays green.
- Reusing `depends_on` (acceptance 4) rather than adding a new "migration pair"
  state is deliberate: the tracker already refuses to satisfy a dependency with
  unmerged work, which is exactly the property expand/contract needs, and a new
  state would be a second thing to keep correct.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 2.
- 2026-08-02 spec-review: REMOVED "diff surface removes an exported symbol" from the signals — at classification time no branch or diff exists, so the criterion was unimplementable and contradicted the Brief's own boundary. Replaced with spec-text signals and an explicit no-code-inspection boundary.
- 2026-08-02 spec-review: ADDED acceptance 1 — the signal list was referenced ("any declared irreversible signal") but its home was never declared, leaving hardcoded-literals vs external-list undetermined.
- 2026-08-02 spec-review: MODIFIED the override criterion — mechanism was unspecified, and the repo's only existing confirmation pattern is interactive, which cannot apply to an unattended advance. Now a recorded artifact in Notes, with silence explicitly not consent.
- 2026-08-02 spec-review: MODIFIED output_spec and acceptance 6 to agree — output_spec said only the contract spec carries `hardened`, the acceptance said every irreversible spec did.
- 2026-08-02 spec-review: ADDED `depends_on: 004` (vacuous check_cmd, same root cause as spec 001).
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7 — write the suite and cases first, see real failures, then implement.
