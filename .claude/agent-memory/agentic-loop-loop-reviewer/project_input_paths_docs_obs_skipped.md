---
name: project_input_paths_docs_obs_skipped
description: spec 013 listed docs/observability.md and scripts/lib/obs.sh in input_paths but neither was touched; the event schema doc still describes agent_stop's old field set and has no row for the new diff_size event type
metadata:
  type: project
---

Spec 013 (`comprehension-capture`) `input_paths`: `scripts/lib/obs.sh`,
`scripts/observe.sh`, `skills/review/SKILL.md`, `docs/observability.md`,
`evals/cases/comprehension-capture/`. `git diff main...claude/idea-013-comprehension-capture --stat`
shows only `scripts/observe.sh`, `skills/review/SKILL.md`, and the new eval
cases changed — `scripts/lib/obs.sh` and `docs/observability.md` have zero
diff. `docs/observability.md:26`'s `agent_stop` row still reads "duration,
summary from the final message, best-effort tokens/model from the
transcript" — no mention of the new `detail.findings_count`, and there is no
row anywhere for the new `diff_size` event this spec added. `scripts/lib/obs.sh`
not needing a change is plausible (it corrected acceptance 2 away from
`obs_shim_tap`, and `obs_event` is a generic append function that doesn't
need per-event-type registration), so that omission may be a stale
`input_paths` rather than a real gap — but the doc omission is a genuine
schema/doc drift with no eval case gating it.

**How to apply:** when a spec's `input_paths` names a docs file describing an
event/field schema, check the diff touches it whenever new fields or event
types are added — don't assume "the code eval passed" implies the docs
stayed in sync, since no case in this suite reads `docs/observability.md`.
See also [[project_002_skill_not_wired_and_005_gap]] — same pattern (an
`input_paths` entry silently skipped) on a prior spec; this is now a 2nd
sighting of "builder touches the code paths but skips a named doc/skill
file" and is worth flagging on sight going forward.

**3rd sighting (spec 019, 2026-08-10):** `templates/.env.example` was listed
in `input_paths` but has zero diff (`git log --oneline -- templates/.env.example`
last touched by spec 018, not 019). Its commented override examples at
lines 43-45 still read `OPENROUTER_MODEL_KIMI=moonshotai/kimi-k2` and
`OPENROUTER_MODEL_MINIMAX=minimax/minimax-m2` — the exact ids spec 019
just retired for being under the 1M-context bar. A user copying the
example verbatim would set an override to the id the spec fixed. Always
`git log -- <path>` every declared `input_paths` entry against the diff
range before signing off; three specs in a row have shipped this exact gap.
