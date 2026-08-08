---
name: feedback-input-paths-scope-omission
description: Watch for specs whose Acceptance criteria require editing a file not listed in input_paths (e.g. templates/factory-spec.md)
metadata:
  type: feedback
---

Rule: when an Acceptance criterion requires a new persisted artifact/field
(e.g. "the spec records which condition ended the interview"), check whether
the file that would need to change (often `templates/factory-spec.md`, the
spec template) is actually listed in the Brief's `input_paths`. If it isn't,
that's a real ambiguity finding — a competent implementer might: (a) add an
out-of-scope template edit anyway, (b) cram the data into an existing free-text
field (Notes/Revision log) instead of a structured one, or (c) skip it as
"not in my input_paths". First observed: spec 006
(`factory/specs/006-grilling-stop-condition.md` acceptance 4) requires the
emitted spec to record a terminating condition, but `input_paths` only lists
`skills/spec/SKILL.md` and `evals/cases/grill-stop/` — `templates/factory-spec.md`
has no such field (checked: only `profile: standard` in frontmatter, no
stop-condition field).

**Why:** this repo's spec format explicitly scopes `input_paths` as "the seams
this change touches" (see `templates/factory-spec.md`), so an omission here is
a genuine scope gap, not reviewer pedantry.

**How to apply:** two-strikes — this is strike 1. If a second spec in this repo
repeats the pattern (acceptance requires template/config changes not in
input_paths), treat it as a repo-wide gap worth escalating in review commentary
rather than a one-off per-spec finding. See [[project-spec-gate-conventions]].

**Strike 2 (2026-08-02): spec 011** (`factory/specs/011-comprehension-metrics.md`).
Acceptance 1 requires "diff size per spec" and "review findings per unit of
diff" as proxies "derived entirely from data the event log already
captures" (objective, line 17) — but neither diff size/bytes nor a
findings[] count is captured by any `obs_event` call site (checked
`scripts/lib/obs.sh` `obs_shim_tap`, `scripts/observe.sh`'s `agent_stop`
overlay). Fixing that would mean editing `scripts/lib/obs.sh` and/or
`scripts/observe.sh` — neither is in `input_paths` (only
`scripts/lib/obs_metrics.jq`, `scripts/observe_metrics.sh`,
`templates/observability/dashboards.md`, `evals/cases/comprehension/` are
listed), and the Brief's own boundary forbids adding new capture anyway.
This is now a two-strike pattern in this repo: **when a spec's Acceptance
requires data/fields that the listed `input_paths` files cannot produce,
say so explicitly as a Brief/Acceptance contradiction, not just a missing
citation** — worth flagging in the review's opening summary as a systemic
gap in how this repo's specs get input_paths right, not only per-spec.

**Strike 3 (2026-08-02): spec 007** (`factory/specs/007-review-severity-and-blockers.md`
AC3, lines 34-35). AC3 requires "a fixed enumerated list held in one place"
of presumptive-blocker structural problems, but the spec text never states
what's on the list (only one example item appears, inside AC5's
Given/When/Then, line 39: "a diff that relocates complexity rather than
reducing it"). The actual 5-item list lives in `docs/osmani-audit.md`
§2.3.3 (lines 564-567: complexity relocated, oversized file with no
decomposition, feature logic in shared modules, near-duplicate helpers,
silent fallbacks) — cited only via `user_intent_verbatim`, never added to
`input_paths` (which lists only `agents/reviewer.md`, `skills/review/SKILL.md`,
`evals/cases/review-severity/`).

**Strike 4 (2026-08-02): spec 009** (`factory/specs/009-attempt-ledger.md`
AC5, lines 38-39). AC5 says "the existing size discipline applies and the
oldest entries are consolidated" as though automated consolidation already
exists — grepped `skills/`, `scripts/` for LEARNINGS.md pruning logic, found
none; the only "existing" mechanism is a manual, unchecked human checklist
line (`templates/RUNBOOK.md:183`, a `- [ ]` item). None of spec 009's
`input_paths` (`templates/LEARNINGS.md`, `skills/build/SKILL.md`,
`skills/review/SKILL.md`, `evals/cases/ledger/`) implement it either. Same
root cause as strikes 1-3: an Acceptance criterion assumes a
definition/mechanism is already established when it is not, and doesn't
name where it should come from.

**Confirmed systemic at 4 strikes across specs 006, 011, 007, 009** — flag
this class by default on every future spec-review-gate pass in this repo:
for every SHALL that says "a fixed list", "the existing X", or "per doc Y",
verify the content/mechanism is either inlined in the spec or its source
file is actually in `input_paths`, and if it claims an "existing"
mechanism, grep the codebase to confirm it's implemented, not just
described as a norm.
