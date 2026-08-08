---
name: project_reopen_cycle_metric_aggregation_gap
description: Per-spec metrics specs rarely say how to aggregate leaf-event data across reviewing->building reopen cycles (sum vs last vs first)
metadata:
  type: project
---

`scripts/lib/tracker.sh:16` lifecycle is `... built -> reviewing -> pr-open
-> done`, and `reviewing -> building` is a real transition (a spec can be
sent back and reworked before merge). `obs_metrics.jq:88-89` `reopens`
already counts these `to_status building` transitions after the first — so
multi-cycle specs are a real, common case, not a hypothetical.

For any spec that adds a new per-spec-id field captured on a **leaf event**
(shim_call/agent_stop/headless_iteration — see `obs_metrics.jq:19`), check
whether that field can be emitted more than once per spec (once per
review/build cycle). `spec_rollup`'s existing `$work` aggregation (line
71-79) sums/counts across ALL leaf events for a spec_id — so a naive
implementation of a new field would silently sum across reopen cycles
(inflating totals) unless the spec explicitly says "first", "last", or
"sum, and that's intended."

1st strike: spec 011 (comprehension proxies) — diff size and review-finding
count are captured "at the point a diff exists" / "from a completed blind
review" (013 acceptance 1/2) with no statement of which cycle's data
"diff size per spec" refers to when a spec was rejected and resubmitted.

2nd strike (confirmed directly, not via 011): spec 013 itself
(`comprehension-capture`), acceptances 1/2 as read on their own terms —
`output_spec` speaks of "the size of the diff it produced" and "the number
of findings its blind review raised" in the singular, but nothing in the
spec says whether a reopened spec (real transition per
`scripts/lib/tracker.sh`) gets one capture event per cycle summed, only the
last, or only the first. The gap survived the split from 011 into 013
unaddressed.

**How to apply:** when reviewing a spec that reports a per-spec-id numeric
proxy sourced from a leaf event, check reopens/cycle count semantics before
approving — ask "what happens if this spec has reopens > 0" explicitly.
