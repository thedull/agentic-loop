---
id: 005
title: Give profile hardened a real security review payload
status: queued
profile: standard
created: 2026-08-02
depends_on: 001 004
claimed_by:
branch:
pr:
---

# Spec 005 — Give profile hardened a real security review payload

## Brief (the delegation contract)

- **objective**: make `profile: hardened` route to a deeper security review than the standard blind pass, so the second switch position does something.
- **user_intent_verbatim**: backlog item 4 of `docs/osmani-audit.md` §2.7 — security today is one bullet in the review axes (`skills/review/SKILL.md:47`), and that bullet is the entirety of our posture for shipped code.
- **input_paths**: `agents/reviewer.md`, `skills/review/SKILL.md`, `evals/cases/hardened/`
- **boundaries_non_goals**:
  - Does NOT run on every spec. Always-on threat modeling is the ceremony this repo rejects, and a universal flag is a worthless flag.
  - Does NOT add a scanner, a CVE feed, or any network dependency.
  - Does NOT change the blind-review protocol — the hardened reviewer is still blind to the builder's reasoning.
  - Does NOT decide which specs are hardened; spec 002 does that, and a human can set it by hand.
- **output_spec**: a `hardened` spec's review additionally produces a trust-boundary sketch with abuse cases, an OWASP-class sweep, and a dependency/supply-chain check — each finding carrying evidence like any other, and the whole payload discoverable by the marker spec 001's acceptance 7 tests for.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. The hardened payload SHALL be discoverable by a positive marker.
   - Given the review stage checking whether the hardened path is installed, when the payload is present, then the marker spec 001 tests for resolves; and when it is absent, then spec 001's acceptance 3 refusal fires.
2. A hardened review SHALL produce a trust-boundary sketch with at least one abuse case per boundary.
   - Given a `hardened` spec whose change crosses a trust boundary, when the review completes, then the output names each boundary crossed and, for each, a concrete abuse case — not a generic reminder that boundaries exist.
3. A hardened review SHALL sweep the named OWASP classes and report each as checked or not-applicable with a reason.
   - Given a hardened review, when it completes, then every class in the declared list has an explicit verdict; a class silently omitted is a failure, because silence is indistinguishable from "did not look".
4. A hardened review SHALL check dependency and supply-chain surface when the diff touches it.
   - Given a diff that adds or upgrades a dependency or touches a lockfile or install script, when the hardened review runs, then it reports the change, its reachability from the spec's own code paths, and whether a fix or alternative exists.
5. Hardened findings SHALL meet the same evidence bar as every other finding.
   - Given any hardened finding, when it is reported, then it cites file:line or command output before stating severity — the existing rule at `agents/reviewer.md:29`, not a relaxed one.
6. A hardened review SHALL NOT merge, and SHALL NOT be reachable from the dark lane.
   - Given a `hardened` spec, when the review completes with zero findings, then the terminal state is still an open PR; and given any attempt to combine `hardened` with dark-lane eligibility, then it is refused.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite hardened
```

**Build order (spec 004 acceptance 7).** This names a **new suite of its own**,
never an existing one: a suite with passing cases can never fail first
(`--suite tracker` passes 24 today), and two specs sharing a suite make each
other's gate vacuous depending on claim order. But a *missing* suite is not a
red gate either — it exits 4 ("nothing ran"), and "no test" is not "a failing
test". So the builder's first step is to create this suite and its cases, run
the check, and see them genuinely fail (exit 1). Only then implement.

Cases are `kind: bash-unit` over fixture diffs, plus the anchored-rubric path
where a judgment is genuinely under test — never a judge for the mechanical
parts. Mutation-test acceptance 3 hardest: delete one class from the declared
list and confirm the case fails rather than passing quietly.

## Notes / decisions (append-only)

- Acceptance 3's insistence on an explicit not-applicable verdict rather than
  silence is the hard-to-reverse call. It makes hardened reviews more verbose,
  which is a real cost. It is worth it because the whole failure mode this spec
  exists to fix is a security check that was never run being indistinguishable
  from one that found nothing — the same silent-success class as spec 004.
- Deliberately no scanner: a dependency scanner is a network dependency, a
  maintenance burden, and a source of findings with no evidence attached, all of
  which this repo has reasons to avoid. The hardened pass reasons about the diff
  in front of it.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-02 spec: ADDED initial spec from `docs/osmani-audit.md` §2.7 backlog item 4.
- 2026-08-03 grill: MODIFIED build order per spec 004 acceptance 7.
