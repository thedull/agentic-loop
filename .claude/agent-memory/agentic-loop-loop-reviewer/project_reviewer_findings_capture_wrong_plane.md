---
name: project_reviewer_findings_capture_wrong_plane
description: obs_shim_tap cannot see loop-reviewer's findings[] — the reviewer runs as a Task-tool subagent, never through a call_*.sh shim; the only touchpoint is observe.sh's SubagentStop hook parsing last_assistant_message as opaque text
metadata:
  type: project
---

`agents/reviewer.md` (the `loop-reviewer` subagent) is invoked exclusively via
Claude Code's native Task-tool subagent mechanism from `skills/review/SKILL.md`
step 4 ("Delegate to the loop-reviewer subagent") and `skills/spec/SKILL.md` —
never through any of the `call_*.sh` scripts (`call_sol.sh`,
`call_openrouter.sh`, `call_ollama.sh`, `call_fable.sh`). `obs_shim_tap`
(`scripts/lib/obs.sh`) is only ever invoked from `scripts/lib/common.sh`
(`grep -rln obs_shim_tap` returns only those two files) — it wraps the
`call_*.sh` envelope pipeline (`finalize_envelope` → `validate_envelope` →
`obs_shim_tap`), which the reviewer subagent's output never passes through.
So `obs_shim_tap` has zero access to the reviewer's `findings[]`.

The only touchpoint with visibility into the reviewer's raw output is
`scripts/observe.sh`'s `SubagentStop` hook case (fires automatically per
`hooks/hooks.json`, filtered to `agent_type` matching `loop-*`), which reads
`.last_assistant_message` — but only ever as **opaque text**, truncated to
`.[0:1000]` for the `summary` field (`observe.sh:217`). `docs/observability.md`
row 26 confirms: "`agent_stop` (duration, summary from the final message, ...)"
— no structured JSON extraction happens there today, unlike `shim_call`'s
already-validated-envelope extraction.

1st strike: spec 013 (`comprehension-capture`) acceptance 2. The spec's own
`user_intent_verbatim` blames `obs_shim_tap` for the missing capture
("`obs_shim_tap` records `detail.artifacts` and `detail.caveats_count`
only"), which points a builder at the wrong plane — `obs_shim_tap` can never
see this data no matter how it's extended. The correct site is
`observe.sh`'s `SubagentStop` case parsing the untruncated
`.last_assistant_message` (available pre-slice in the same jq filter) as
JSON, with `fromjson?` failure naturally (if a little accidentally) mapping
to null. Also: if a builder reuses the already-truncated `summary` string
instead of the raw field, any review whose JSON exceeds 1000 chars —
trivial with a couple of findings that carry `evidence` strings — silently
degrades a *completed* review to null.

**How to apply:** for any future spec that wants to capture data from a
subagent's *content* (not just duration/tokens), check whether that subagent
is invoked via Task-tool (no shim access, only opaque `last_assistant_message`
text via the hook) or via a `call_*.sh` script (full structured access via
`obs_shim_tap`). Don't trust a spec's own diagnosis of "where existing capture
already reads related fields" without confirming the cited mechanism can
reach the new field's source at all. See also
[[project_primary_objective_unenforced_by_checkcmd]] for the parallel gap on
the diff-size half of the same spec.
