---
name: project-agentic-loop-spec-gate
description: agentic-loop repo runs a blind spec-review gate on factory/specs/*.md before build; specs commonly claim a metric/proxy is "derived entirely from existing captured data" — verify against scripts/lib/obs.sh and scripts/lib/obs_metrics.jq before trusting it
metadata:
  type: project
---

Repo: agentic-loop plugin (bash + jq, no build step, no package manager —
confirmed no package.json/requirements.txt/Gemfile at repo root). Specs live
in `factory/specs/NNN-slug.md` with a `depends_on` frontmatter field; each
spec's `check_cmd` is meant to name a brand-new `evals/cases/<suite>/`
directory (per spec 004's rule) so the Red Gate fails for the honest reason
the suite doesn't exist yet, not because of a shared-suite collision.

**Why:** spec 011 (2026-08-02, comprehension-metrics) claimed all four of its
proxies were "derived entirely from data the event log already captures."
Checking the actual capture code (`scripts/lib/obs.sh` `obs_shim_tap`
overlay, and the `agent_stop` overlay in `scripts/observe.sh`) showed
`findings[]` count is never captured into any event, and no event/detail
field anywhere captures diff size/bytes/line-count. Two of the four "already
captured" proxies were not actually derivable. Separately, the existing
`reopens` field in `scripts/lib/obs_metrics.jq` counts pre-merge cycles back
into `building` status, but the spec's Notes described re-open rate as a
*post-merge* "human didn't understand it when they merged it" signal — the
tracker state machine (`scripts/lib/tracker.sh`) has `done` as a terminal
state with no reachable post-merge-reopen transition, so that semantic
cannot be represented by any existing capture either.

**How to apply:** when a spec in this repo claims a metric/proxy is
"derived from existing captured data" or "reuses an existing field," don't
take the claim at face value — grep the actual event-emission call sites
(`obs_event` call sites in `scripts/observe.sh`, `scripts/lib/tracker.sh`,
`scripts/lib/obs.sh`, `scripts/run_headless.sh`, `scripts/lib/bench.sh`,
`scripts/lib/usage_gate.sh`) and the rollup logic in
`scripts/lib/obs_metrics.jq` to confirm the field actually exists with the
claimed semantics before accepting the spec's Brief/Notes as accurate. This
is a two-strikes-worth-watching defect class for this repo's spec-review
gate — check it again on the next spec-review pass over `observe_metrics.sh`
or `obs.sh`-adjacent specs.
