---
name: config
description: >-
  Toggle the agentic-loop feature flags for the current project: observability
  (event log + tree reports), minimize (code-minimization ladder in build
  briefs), grill (pre-planning interview), guards (reviewer quality gates) and
  summarize (Ollama fallback summaries in reports). Use when the user wants to
  turn a loop feature on or off, check what is enabled, or render an
  observability report.
---

# agentic-loop:config — feature flags

All optional loop features live behind explicit, default-off flags in ONE
file: `.agentic/config.json` in the current project. This skill is the only
writer of that file. Invocations:

```
/agentic-loop:config                          → status (all features)
/agentic-loop:config <feature> on|off         → toggle
/agentic-loop:config <feature> status         → one feature
/agentic-loop:config render [--tty]           → observability report (delegates
                                                 to scripts/observe_render.sh)
```

## The features

| Feature | What it enables | Third-party dependency |
|---|---|---|
| `observability` | Unified JSONL event log (`.agentic/observability/`) capturing every subagent, shim call, headless iteration and factory transition; renderable as an HTML/tty tree | none |
| `minimize` | The code-minimization decision ladder is injected into build-stage worker briefs (smallest sufficient diff) | ponytail (rules content; plugin optional) |
| `grill` | A relentless pre-planning interview runs before `loop-planner` decomposes ambiguous or high-stakes requests | grill-me skill |
| `guards` | Clean-code + test quality-gate criteria are added to the reviewer's blind-review checklist | guard-skills (criteria content; plugin optional) |
| `summarize` | The report renderer fills summary-less nodes via local Ollama (free) | ollama running locally |

## Config file shape

```json
{
  "observability": { "enabled": true, "all_agents": false },
  "minimize":      { "enabled": false, "agent_judgment": false },
  "grill":         { "enabled": false, "agent_judgment": false },
  "guards":        { "enabled": false },
  "summarize":     { "enabled": false },
  "_meta":         { "updated": "<iso date>" }
}
```

- `agent_judgment: true` permits the ORCHESTRATOR to enable that feature
  per-task on its own judgment. Every judgment toggle MUST be recorded:

  ```bash
  ./scripts/observe.sh emit feature_toggle \
    '{"detail":{"feature":"minimize","scope":"task 003","reason":"mechanical bulk edit","decided_by":"agent"}}'
  ```

  Never judgment-enable anything metered in unattended (factory/headless)
  stages — same rule as metered escalation.
- `install_declined: true` on a feature records that the user declined
  installing its third-party dependency: never re-offer, run without it.

## Steps

1. Read `.agentic/config.json` if it exists (create `.agentic/` and the file
   with all features `enabled: false` on first write; never create it for a
   pure status read — report "no config, all features off" instead).
2. **status**: print a short table — feature, enabled, dependency state
   (installed / missing / declined). Detect dependencies cheaply: `observability`
   none; `summarize` → `curl -sS --max-time 2 http://localhost:11434/api/tags`;
   `minimize`/`grill`/`guards` → look for the plugin/skill in `claude plugin list`
   output or their marketplace names (ponytail, caveman, guard-skills, skills).
3. **`<feature> on`**:
   a. If the feature has a third-party dependency that is MISSING and
      `install_declined` is not set: show the install command
      (e.g. `/plugin marketplace add DietrichGebert/ponytail` then
      `/plugin install ponytail@ponytail`) and ask the user:
      **install now / enable anyway (applies once installed) / cancel**.
      If they decline installing but still want the feature, set
      `install_declined: true` alongside `enabled: true`.
   b. Update the file with jq (preserve unknown keys):
      `jq '.<feature>.enabled = true | ._meta.updated = "<today>"' …`
   c. If observability was just enabled, mention: events start with the NEXT
      session/shim call; `AGENTIC_OBSERVE=1` forces it for one-off runs;
      `.agentic/` is gitignored so nothing lands in git.
4. **`<feature> off`**: set `enabled: false`. Do not delete the entry (history
   of `install_declined` etc. must survive).
5. **render**: run `./scripts/observe_render.sh` (add `--tty` if asked for a
   terminal view; `--summarize` only if the `summarize` flag is enabled).
   If the scripts are not scaffolded into this project yet, run them from the
   plugin root instead (this file lives at `<plugin-root>/skills/config/SKILL.md`).

Keep output terse: a status table or a one-line confirmation. Never enable a
feature the user didn't name. If asked about a feature not in the table, say
it doesn't exist rather than inventing one.
