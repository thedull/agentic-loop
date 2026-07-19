# Field report — premiere-bridge (2026-07-19)

**Project:** `~/Projects/Claude/premiere-bridge` — installing and field-testing
an Adobe Premiere Pro MCP bridge (vendor server + CEP panel), then running a
real editing pilot on a podcast episode. One full working day, one
orchestrator session (Fable 5), interactive throughout.

**Loop usage:** scaffolded via `/agentic-loop:init`; the user then redirected
to direct implementation of the project's research handoff. The factory/spec
flow, worker envelopes, and Sol escalation were **not exercised** — no verdict
on those from this run. What follows is what the day actually tested.

## Validated: the epistemic core, applied solo

The loop's central discipline — *verify after every write, never trust a
worker's (here: a tool's) self-reported success* — was applied by the
orchestrator directly against MCP tool calls, and it carried the day. Silent
failures caught by read-back verification in ONE day:

1. `ripple_delete` (and every unimplemented "expanded" tool) ACKed
   `accepted:true` while doing nothing — caught by structure read-back,
   confirmed in vendor source (a default case ACKs all unknown tools).
2. `undo` claimed success, reverted nothing (twice, incl. a controlled probe).
3. `razor_timeline_at_time` landed every cut at `t × 1.001` (NTSC timecode
   conversion bug) — caught by comparing requested vs. read-back positions.
4. "Ripple" deletes were track-local and non-deterministic (lifted once,
   rippled once in the same session) — caught by pairwise A/V read-back.
5. `create_caption_track` "succeeded"; exported frames showed cue #1
   rendering at minute 2 AND minute 6 — timing silently broken.
6. A **user edit made between orchestrator calls** shifted the timeline
   1.3 s; the next cut, aimed with cached coordinates, landed in wrong
   content — caught before removal by re-reading structure.
7. Transition tools return "completed but not verified" (no read API) —
   correctly treated as unproven rather than done.
8. brew's ffmpeg lacks libass; the failure surfaced as misleading
   filter-parse errors two layers up.

Rule of thumb that emerged: **verify against the state you can read, by the
cheapest independent channel available** — structure reads, file existence,
ffprobe duration (which twice confirmed edits to the microsecond), exported
frames read as images.

## Task-shape lesson (docs-worthy)

This work was stateful, interactive, MCP-heavy integration against ONE live
application connection: sequential mutations, each dependent on live state,
verified before the next. Worker fan-out had nothing to bite on; the
orchestrator doing domain work itself was *correct*, and CLAUDE.md's
"conversation vs workflow" rule held as written. Suggested doc note: name
this exception class explicitly — "hub does no domain work" presumes
parallelizable, stateless-ish subtasks; live-app puppeteering is the
counter-case. (A second session-shaped lesson: the human edited the live app
mid-session — rule 6 above — so any cached mapping of external state must be
re-derived immediately before each mutation.)

## Untested here

Factory/spec flow (queue empty, spec-001 interview interrupted), Sol
escalation (no structural trigger fired — disagreeing critics never arose in
solo verification work), worker envelopes, cheap-iteration mode. No evidence
either way.

## Evidence

Raw log: `premiere-bridge/VERSIONS.md` (smoke-test log, rounds 1–4) — every
bug above with dates, repro, and the working workaround. Skill-codified
procedures: `premiere-bridge/.claude/skills/edit-podcast/SKILL.md` (hard
rules + verified cut procedure).
