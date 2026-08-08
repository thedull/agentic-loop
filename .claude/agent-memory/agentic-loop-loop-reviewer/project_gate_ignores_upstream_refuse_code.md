---
name: project-gate-ignores-upstream-refuse-code
description: tracker_advance's new specd gate (spec 002) only checks for exit 7 from tracker_irreversible, silently letting a broken/missing signal list (exit 2) through to specd — confirmed live.
metadata:
  type: project
---

Spec 002's `tracker_advance` early-return (scripts/lib/tracker.sh:507-521) guards
the `specd` transition by calling `tracker_irreversible` and checking only
`$_irc -eq 7`. But `tracker_irreversible` itself has THREE outcomes: 0
(reversible), 7 (irreversible), 2 (broken/missing/empty signal list — refuses
outright, per acceptance 3's fail-closed guarantee). `tracker_advance` treats
exit 2 the same as exit 0 and lets the spec through to `specd` unclassified.

Confirmed live: with `IRREVERSIBLE_SIGNALS` pointed at a nonexistent file,
`tracker.sh advance <file-with-"drop the legacy email column"-in-objective>
specd` exits 0 and sets `status: specd` — the exact case acceptance 3 says
must refuse, at the one integration point (the spec-stage gate) where it
actually matters. The standalone `tracker.sh irreversible` command does fail
closed in isolation; the bug is only at the call site that forwards a
subset of its exit codes.

**Why:** this is a general pattern risk in this repo — a function with a
"refuse" exit code (2, 5, 6, etc. — see [[project_exit_code_4_already_overloaded]])
that a caller integrates via `|| _rc=$?` and then pattern-matches on ONE
specific code. Any refuse code the caller doesn't explicitly check silently
falls through as success.

**How to apply:** whenever a gate/guard function is wired into a caller via
`fn ... || rc=$?; if [[ $rc -eq N ]]; then refuse; fi`, check what the callee's
OTHER non-zero exit codes mean and whether the caller silently treats them as
success. Mutate the callee to return each of its documented refuse codes and
re-run the caller, not just the callee's own eval cases.
