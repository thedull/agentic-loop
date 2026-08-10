---
id: 016
title: Require a code location on every adversary finding
status: specd
profile: standard
created: 2026-08-08
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 016 — Require a code location on every adversary finding

## Brief (the delegation contract)

- **objective**: make every adversary finding carry either a machine-checkable location or an explicit statement of where it looked — enforced by a response schema and by envelope validation, not by prompt text a model can decline.
- **user_intent_verbatim**: "(§6 item 3) Require a machine-checkable code location on every adversary finding... Turn 'cite your evidence' from a prompt request into a refusal." (2026-08-08). Absence handling settled by owner ruling the same day: *"Null location allowed, but must say where it looked."*
- **input_paths**: `scripts/call_sol.sh`, `scripts/lib/common.sh`, `scripts/lib/validate_envelope.jq`, `agents/reviewer.md`, `agents/reviewer-frontier.md`, `evals/cases/findings-schema/`, `evals/fixtures/`
- **boundaries_non_goals**:
  - Does NOT adopt a numeric `confidence` field. `templates/LOOP_POLICY.md:51-52` forbids acting on self-reported confidence; `confidence_ordinal` stays exactly as it is. A 0–1 score is false precision about a quantity the model cannot access.
  - Does NOT change what the reviewer is asked to look for. `scripts/call_sol.sh:59-60` scopes it to correctness and requirement gaps; this spec changes the *shape* of a finding, never its subject.
  - Does NOT require findings from non-adversary workers. `findings` defaults to `[]` for every other tier and stays optional.
  - Does NOT put an LLM anywhere in the check. Every rule here is a set or type operation on committed JSON.
  - Does NOT assume the artifact under review is code. The adversary reviews *"any candidate artifact"* (`templates/LOOP_POLICY.md:16`) — a doc or a spec has files and lines too.
- **output_spec**: a `findings` array in which every item carries a `location` field that is either an object `{file, line_start, line_end}` or `null`; when it is `null` the item SHALL also carry a non-empty `searched` scope. Requested via a provider response schema and enforced at receipt by `validate_envelope.jq`.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. Every adversary finding SHALL carry a `location` object or an explicit searched scope.
   - **Shape, stated once so two implementers cannot diverge:** `location` is a single field on the finding. Its value is either the object `{file, line_start, line_end}` or `null`. The three keys live *inside* `location` and never as flat siblings on the finding.
   - Given `location: {file, line_start, line_end}` with all three present, when the envelope is validated, then it passes.
   - Given `location: null` and a non-empty `searched` naming what was examined, when the envelope is validated, then it passes.
   - Given `location` absent entirely, or `location: null` with no `searched`, or a `location` object missing any of its three keys, when the envelope is validated, then validation fails and the shim exits 4.
2. The request SHALL carry a provider-enforced response schema, and the validator SHALL remain the backstop.
   - Given an adversary call, when the request is built, then it includes a response schema declaring the findings shape — `scripts/call_sol.sh:92-99` sends none today.
   - Given a provider that ignores or does not support the schema, when the response arrives, then acceptance 1's validation still refuses a malformed finding. The schema is an optimisation; the validator is the gate.
3. Line numbers SHALL be structurally sane.
   - Given `location.line_start` or `location.line_end` that is not an integer ≥ 1, or `location.line_end < location.line_start`, when the envelope is validated, then validation fails.
   - Given a finding about a whole file with no meaningful line, when it is emitted, then it uses the `location: null` + `searched` form rather than inventing line 1.
4. `searched` SHALL be a commitment, not an escape hatch.
   - Given `searched` present but empty, whitespace-only, or absent while `location` is `null`, when the envelope is validated, then validation fails.
   - Given `searched` supplied alongside a non-null `location`, when the envelope is validated, then it passes and `searched` is ignored — belt and braces is not an error.
5. Existing workers SHALL be unaffected.
   - Given any envelope whose `findings` is absent or `[]`, when it is validated, then behavior is identical to today.
   - Given the existing `envelope` suite, when it runs after this change, then every case still passes.
6. The severity vocabulary SHALL stay ordinal and SHALL NOT gain a numeric sibling.
   - Given a finding carrying a numeric confidence or score field, when the envelope is validated, then validation fails rather than silently accepting it.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite findings-schema
```

**Build order (spec 004 acceptance 7).** New suite of its own. Write the suite
and its cases first, see them genuinely fail (exit 1), then implement.

**Why this check_cmd is vacuous today, and why that is not a defect in this
spec.** Run against the untouched tree it exits 0 with `0 pass, 0 fail, 0
skipped`, because `evals/run_eval.sh` has no zero-case guard yet — that guard is
spec 004, which is `queued`. This spec's `depends_on: 004` is precisely what
keeps it from being claimed before the guard exists: the tracker satisfies a
dependency only with `done`. The spec-review gate will correctly flag this on
every spec in the queue until 004 lands, and the correct response is the
dependency, not a different check_cmd.

Fixtures under `evals/fixtures/`: a located finding, a null-location finding
with `searched`, a null-location finding without `searched`, a finding with
`line_end < line_start`, a finding carrying a numeric confidence, and a
non-adversary envelope with no `findings` key at all. Acceptance 2 needs a
fixture where the mocked provider response ignores the schema entirely — that
case is the one proving the validator is load-bearing rather than decorative.

Mutation-test acceptance 1 and 4 in particular: delete the `searched` emptiness
check and confirm a case fails. A `searched: ""` that passes turns the whole
escape hatch into an unconditional bypass.

## Notes / decisions (append-only)

- **Null location is allowed, but only against a stated scope** (owner ruling
  2026-08-08). The alternative considered and rejected was dropping unlocatable
  findings: it silently deletes something the reviewer considered real, and a
  dropped finding leaves no trace anywhere. Rejecting the whole envelope was
  also considered and rejected — one unlocatable finding would discard the most
  expensive call in the system. Requiring `searched` keeps the model committed
  to having looked somewhere without suppressing the absence class, which recent
  reviews showed is where several of the most valuable findings live.
- **The validator, not the schema, is the gate** (acceptance 2). Response-format
  support varies by provider and by model, and this shim already targets two
  transports. A design that trusts the request-side schema would be a gate that
  silently stops gating the moment a provider drops the parameter.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-08 spec: ADDED from `docs/codex-subscription.md` §6 item 3, after §2.2 found OpenAI's codex-plugin-cc schema requires a code location on every finding while ours asks for evidence in prose.
- 2026-08-08 grill: SETTLED the absence case by owner ruling — `location: null` permitted only with a non-empty `searched`.
- 2026-08-08 spec-review: MODIFIED acceptances 1, 3 and 4 to pin the wire shape. The gate found `{file, line_start, line_end}` and `location: null` juxtaposed without saying whether the three keys nest under `location` or sit flat beside it — two self-consistent readings producing different schemas and different jq paths. `location` is now one field holding an object or null.
- 2026-08-08 spec-review: ADDED the build-order note that this check_cmd exits 0 today because spec 004 is unbuilt, and that `depends_on: 004` is the mitigation rather than a different check_cmd.
- 2026-08-10 build: ADDED `agents/reviewer.md` and `agents/reviewer-frontier.md` to `input_paths`. Both declare a `findings` shape (`reviewer.md:65`, `reviewer-frontier.md:53`) carrying claim/evidence/severity and no location. The validator gates on the presence of `findings`, not on the worker name — an allowlist of names is defeated by a rename — so leaving these two unchanged would have had the system instruct its own reviewers to emit a shape it refuses elsewhere. Boundary "does NOT require findings from non-adversary workers" is unaffected: an absent or empty `findings` is still untouched.
- 2026-08-10 review: CORRECTED the enforcement claim in the entry above, which the blind review found overstated. Precisely where the rule bites, and where it does not: **(gated)** every `call_*.sh` shim, because `finalize_envelope` pipes through `validate_envelope()` (`scripts/lib/common.sh:226,239`) and exits 4; **(gated at eval time)** `headless-agent` cases carrying an `envelope_valid` check, including `evals/cases/reviewer/040-seeded-sql-injection.json`, which runs `loop-reviewer` for real — but only under `--live`, so it is not exercised in a free sweep; **(instructed only)** a Task-tool subagent's envelope read by the orchestrator at runtime. Nothing pipes that through the validator: `skills/build/SKILL.md:64` says "validate every returned envelope" in prose, and `scripts/observe.sh` treats the subagent's last message as opaque text. So for the two agent files this change is a prompt improvement plus a `--live` eval gate, NOT a receipt-side refusal. Recorded as a follow-up rather than fixed here: gating Task-tool envelopes needs a new validation seam in the orchestrator path, which is a separate spec and outside this one's `input_paths`.
- 2026-08-10 build: CORRECTED two gaps that mutation testing found, both in the tests rather than the implementation. (a) No case covered `location` ABSENT while `searched` was present — acceptance 1 refuses that (absent is not the same state as null), but deleting the guard went undetected until case 025 was added. (b) `line_end` integrality was asserted nowhere: `line_start` had three cases and `line_end` had none, so its check could be deleted freely; cases 026 and 027 close that. Also REMOVED the combined has(file, line_start, line_end) check from the validator — a missing key reads as null and each per-key check already refuses null, so the combined check was undetectable when deleted and was therefore not a guard.
