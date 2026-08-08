---
name: tracker-skip-reason-conflated
description: "tracker_claim's skip path and _tracker_obs_skip hardcode reason/message text as depends_on-specific (\"waiting on depends_on\" / reason: \"depends_on unmet\") even when the true skip cause is unrelated (e.g. spec 001's profile refusal) — skipped[] entries are tagged internally but the aggregate message/event reason is not"
metadata:
  type: project
---

`scripts/lib/tracker.sh`'s `tracker_claim()` (as of spec 001) appends
`"$(basename "$f") [profile]"` to `skipped[]` for a profile-unclaimable spec,
distinguishing it from a plain depends_on skip *within the array entry*. But
the caller-facing stderr line — `"tracker: nothing claimable — ${#skipped[@]}
$from item(s) waiting on depends_on"` — and the `_tracker_obs_skip` event's
`detail.reason` field are both hardcoded to depends_on-only phrasing
regardless of why any given item was skipped. Confirmed live: claiming a
queue containing only a `profile: dark` (or invalid-profile) spec, with no
depends_on involved at all, still prints "...waiting on depends_on" and exits
1 — indistinguishable, at the aggregate-message/event level, from a real
dependency stall.

**Why:** `skills/build/SKILL.md` step 2 tells the build-loop agent to read
that exact stderr line to decide what to do next ("dep-waiting specs become
claimable on their own once you merge their dependencies; never build one by
hand around the gate") — advice that is wrong for a profile-skip, which
never resolves on its own and needs a human to fix the value or ship spec
005/015. `skills/build/SKILL.md` and `skills/review/SKILL.md` (both in spec
001's own `input_paths`) were not updated to mention `profile` at all
(`grep -c profile` = 0 in both).

**How to apply:** when a claim/skip loop grows a second skip reason, check
whether the aggregate human-facing message and any observability `reason`
field were updated to disambiguate, not just the per-item list. A `[tag]`
suffix buried inside an array element that's only visible via the raw event
payload does not count as "distinguishable" for a caller reading the
one-line stderr summary. 1st strike: spec 001.
