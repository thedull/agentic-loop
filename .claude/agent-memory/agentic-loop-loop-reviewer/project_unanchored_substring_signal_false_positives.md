---
name: project-unanchored-substring-signal-false-positives
description: spec 002's irreversibility classifier matches signals as raw substrings with no word boundary — "drop the" fires inside "backdrop theme"/"eavesdrop the logs" — contradicting its own "near-zero false positives" design goal.
metadata:
  type: project
---

`tracker_irreversible` (scripts/lib/tracker.sh, spec 002) matches each line of
`templates/irreversible-signals.txt` as a raw case-folded substring
(`[[ "$hay" == *"$s"* ]]`) against the spec's objective/output_spec/input_paths
text. Confirmed live: a spec whose objective is "update the backdrop theme
colors and eavesdrop the logs for debug" classifies irreversible (exit 7),
because "drop the" (a declared signal) is a substring of "backdrop theme" and
"eavesdrop the".

**Why:** spec 002's own Notes (2026-08-03 owner ruling) state the accepted
trade explicitly: "near-zero false positives, at the price of missing any
irreversible class nobody enumerated." Unanchored substring matching breaks
that half of the trade — the signal list as shipped WILL false-positive on
ordinary English containing the signal as a substring of a longer word.

**How to apply:** for any future spec touching this signal list or a similar
substring-matching gate, check whether matches are word-boundary-anchored.
None of the 10 irreversible-suite eval cases test a false-positive fixture
(a spec containing a signal-as-substring-of-an-innocent-word) — this is a real
gap in evals/cases/irreversible/, not just an implementation nit.
