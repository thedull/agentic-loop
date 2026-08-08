---
name: grep-count-mechanical-check-weak
description: a bash-unit case that greps a doc/file for two literal substrings (e.g. "exit 4" and "exit 1") and asserts both counts >=1 can pass on text that states the exact opposite of the required distinction — verify by mutating the target text, not just by reading the case JSON
metadata:
  type: project
---

`evals/cases/evalrunner/109-build-skill-distinguishes-exit-4-from-1.json`
(spec 004) asserts `skills/build/SKILL.md` "distinguishes exit 4 from exit 1"
via `grep -c "exit 4"` and `grep -c "exit 1"`, checking only `.four >= 1 and
.one >= 1`. Confirmed live: replacing the correct paragraph with "exit 4 and
exit 1 are both totally fine outcomes, proceed regardless of which one you
see" — the exact inversion the spec (acceptance 7) explicitly calls out as
forbidden — still makes both the raw `cmd` and the full case (run through
`./evals/run_eval.sh --case ...`) pass, exit 0.

**Why:** presence-of-both-substrings is not the same as "distinguishes."
Acceptance 7's own text anticipated this failure mode ("a builder reading it
literally would accept exit 4... which is the exact inversion this spec
forbids") but the case that was supposed to mechanically guard against it
only checks word co-occurrence, not the semantic pairing (which number means
proceed vs. which means don't).

**How to apply:** whenever a case's mechanism for verifying a prose
distinction is `grep -c <token>` for each side of the distinction, try
mutating the target file so both tokens are still present but the meaning is
reversed or garbled, then re-run the case (through the harness, not just the
raw cmd) to see if it still passes. This is the general shape of "test
asserts vocabulary, not semantics" — watch for it whenever a doc-edit
acceptance is checked mechanically via grep.

2nd strike: spec 001 (`profile-switch`), `evals/cases/profile/`. Confirmed by
stubbing the CLI's `profile)` dispatch branch to unconditionally
`echo "standard hardened dark" >&2; exit 2` regardless of the fixture passed
(i.e. the real `tracker_profile` logic never runs for CLI-path cases) and
re-running `./evals/run_eval.sh --suite profile`: cases 203
(invalid-refuses), 205 (trailing-content-refused) and 209
(orthogonal-to-effort) still pass, because each only greps stderr for
word-presence ("standard"/"hardened"/"dark") plus a nonzero exit — never
tying the message to the specific fixture that was actually passed. Same
root cause as the 1st strike (vocabulary co-occurrence stands in for
causality) but here the trigger is a case testing *any* input through a
generic error path, not a doc-mutation. See also
[[project_status_unchanged_test_too_weak]] for the sibling failure mode on
state-machine (not stderr-text) assertions.

3rd strike: spec 003 (`failure-triage`), `evals/cases/triage/`. Two distinct
instances in the same suite:
- `408-reviewer-class-not-behind-guards.json` checks only that "regardless
  of/unconditional/even when guards/not gated" appears within 4 lines of
  "untrusted" in `agents/reviewer.md` — it never checks *structural*
  placement. Moving the whole "Acted-upon untrusted output" paragraph to be
  a bullet INSIDE the flag-gated Guard checklist (so it only fires when
  `guards.enabled` is true — the exact bug acceptance 7 exists to forbid)
  still passes all 11 triage cases, confirmed live by editing
  `agents/reviewer.md` and rerunning `./evals/run_eval.sh --suite triage`.
- `409-...json` is the only case touching acceptances 1 and 5, and it's a
  pure grep-count over `skills/build/SKILL.md` prose (counts phrases like
  "not your reasoning" and "regression test"). The spec's own Build-order
  sketch called for a fixture *payload* test (acceptance 1: a payload
  containing builder reasoning must fail) and a fixture *pair* test
  (acceptance 5: check_cmd passes but no root-cause test exists) — neither
  was built. As written, acceptances 1 and 5 are unenforceable beyond "does
  the instructional prose contain the right words."
Also found in the same suite (separate class, not vocabulary-co-occurrence):
`triage_validate`'s `hypothesis:` check (`scripts/lib/triage.sh:42-43`) has
*zero* fixture coverage — no `no_hypothesis.md` fixture exists (only
no_reproduce/no_localize/no_evidence/none/late/good). Neutering that one
check (`true || _t_die ...`) still passes all 11 triage cases.
