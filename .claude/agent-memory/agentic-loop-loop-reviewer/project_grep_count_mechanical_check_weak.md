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

4th strike: spec 005 (`hardened-review-payload`). Two cases in
`evals/cases/hardened/`, confirmed live by editing `agents/reviewer.md` /
`skills/review/SKILL.md` and rerunning `./evals/run_eval.sh --suite hardened`:
- `507-payload-installed-and-routed.json` only greps for marker/format-line/
  keyword co-occurrence (`grep -c "profile-hardened-payload:"`, `grep -c --
  "- boundary: <from> -> <to>"`, `grep -c -- "- abuse:"`, `grep -c
  "hardened.sh"`, `grep -c "templates/hardened-classes.txt"`). Replacing the
  ENTIRE payload prose (all 5 numbered sub-sections, ~40 lines) with a single
  word `x.` plus the bare marker comment, the format code-block, and four bare
  keyword mentions (`hardened.sh templates/hardened-classes.txt hardened.sh
  hardened.sh`) still passes 507 — and every other case in both the
  `hardened` and `profile` suites (23/23), exit 0.

5th strike: spec 012 (`learnings-consolidation`),
`evals/cases/learnings/609-doctor-surfaces-the-cap.json`. Its entire mechanism
is `grep -c "learnings.sh" scripts/doctor.sh; .wired >= 1`. Confirmed live:
replacing the real wiring (the `if out="$(.../learnings.sh check
./LEARNINGS.md 2>&1)"; then ok ...; else warn ...; fi` block) with a bare
comment `# learnings.sh handles LEARNINGS.md size discipline (not actually
called here)` plus `ok "cross-run memory ok"` — i.e. doctor.sh no longer calls
learnings.sh at all — still passes `./evals/run_eval.sh --suite learnings`
11/11. Acceptance 1's "doctor.sh surfaces this" clause is unenforced beyond
the string "learnings.sh" appearing anywhere in the file, including a comment
disclaiming that it doesn't run.
6th strike: spec 018 (`preflight-cost-estimate`),
`evals/cases/preflight-cost/015-default-threshold-applies.json`. Its `must_find`
only checks the literal word "threshold" appears in stderr — it never asserts
the printed value equals the documented default (1.00 USD, declared at
`scripts/lib/common.sh:256` and in `templates/.env.example`). Confirmed live:
changing `PREFLIGHT_DEFAULT_THRESHOLD_USD="1.00"` to `"9999.00"` (a real
regression that would make the gate refuse almost nothing by default) still
passes `./evals/run_eval.sh --suite preflight-cost` 30/30. Same root cause as
the other strikes (word-presence stands in for the actual assertion) but here
there's no distinction/pairing to garble — the case just never captures or
compares the value it greps for.

- `508-hardened-still-terminates-at-a-pr.json`'s `prTerminal` check
  (`grep -ci "terminal state is an OPEN PR\|Nothing merges here"`) is NOT
  scoped to the awk-extracted hardened section — it greps the whole file, so
  it's satisfied by pre-existing top-of-file boilerplate
  (`skills/review/SKILL.md:15`, "Nothing merges here") that exists
  independent of anything spec 005 added. Confirmed live: deleting the
  hardened-specific "A hardened review still terminates at an open PR"
  sentence from step 3b still passes 508. Separately, its `mergeCmds` check
  IS awk-scoped to a window starting at the first "hardened" match and
  closing after 2 numbered `N. **` headers — but that window is narrow
  enough that a `gh pr merge --squash` instruction added in a *new* section
  anywhere past that window (e.g. right before `## Unattended rules`) is
  invisible to it. Confirmed live: adding such a section still passes 508.
