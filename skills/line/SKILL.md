---
name: line
description: >-
  Shape this project's production line — the factory workflow — without forking
  it: read its regions, add or edit project-owned parts (sequencing, extra
  stages, machine realities like ports and package managers), and adopt an
  existing forked workflow back onto the updatable framework. Use when the
  project's loop needs to differ from the stock one, or when a fork has drifted
  from the plugin. Interactive.
---

# agentic-loop:line — shape the production line

No two factory lines are identical. This project's loop shares the frame —
usage gate, Red Gate, blind review, no metered spend unattended, PR-not-merge —
but its sequencing and its machine realities are its own.

`.claude/workflows/factory.js` **belongs to this project**. Edit it freely.
The exception is the spans marked `owner=plugin`: they carry the safety policy
and stage contracts, and `/agentic-loop:update` refreshes them in place so
improvements arrive. Everything outside those markers is yours and is never
touched by an update.

That split exists because of a real failure: a project with no seam forked its
workflow, and the fork silently dropped the review stage's
`record needs_escalation instead` rule and pinned a skill path to a plugin
version that has since moved. **Forking loses policy by omission.**

## Ground rules

- **Never write inside an `owner=plugin` region.** Not to "just tweak" the
  wording, not to add one line. The merge engine detects it and refuses to
  refresh that region afterward, which quietly freezes the project out of
  exactly the updates this design exists to deliver.
- **Policy is not customizable.** If the ask is "stop recording
  `needs_escalation`, just call Sol", "skip the Red Gate", "let it merge" —
  say plainly that this is plugin-owned safety policy, and offer the
  sanctioned alternative (an addendum, a project stage, or a config flag).
  Never rename a region, flip an `owner`, or move text out of a plugin region
  to get around it.
- **Prefer a script over prose.** A mechanical step belongs in a project
  script the line calls, not in prompt text an agent may skip — the same
  reasoning that made review benches `bench.sh` instead of an instruction.
- Check the plugin already lacks it. `depends_on` sequencing
  (`scripts/lib/tracker.sh`), review benches (`scripts/lib/bench.sh`),
  feature flags (`/agentic-loop:config`) are shipped: a project reinventing
  one of those is drift, not customization.

## Where customization goes

| Want | Put it |
|---|---|
| Machine realities (ports that must stay up, fixture env vars, package manager) | `PROJECT_BUILD_ADDENDUM` / `PROJECT_REVIEW_ADDENDUM` — appended to the plugin's stage prompt |
| Sequencing (serial vs batched, pause vs skip, caps) | `MAX_IDEAS` and the `pipeline()` wiring — project-owned already |
| A whole extra stage | a new `owner=project` region, ideally calling a project script |
| Spec ordering | `depends_on:` in the spec frontmatter — not the workflow |
| A per-PR runnable checkout | `/agentic-loop:config bench on` — not the workflow |

## Steps

1. **Read the current line.**

   ```bash
   ./scripts/lib/workflow.sh regions .claude/workflows/factory.js
   ./scripts/lib/scaffold.sh status "$PLUGIN_ROOT" <type> | grep workflows
   ```

   If it reports `regions-updatable`, say so and offer `/agentic-loop:update`
   first — customizing on top of a stale frame wastes the work. If
   `regions-conflict`, resolve that before anything else: something is edited
   inside a plugin region, or the markers are broken.

2. **Interview — one question at a time.** What differs about this line, and
   *why*: what breaks if the stock behavior runs? Get the concrete fact (the
   port number, the command, the ordering rule), not a vague preference. Stop
   as soon as the change is unambiguous.

3. **Classify before writing.** For each thing the user wants, decide from the
   table above where it goes. If it is policy → refuse per the ground rules and
   offer the alternative. If the plugin already provides it → point at that
   instead. Say which bucket you chose and why.

4. **Write it — project-owned regions only.** Give new regions a stable
   kebab-case name and mark them:

   ```js
   // @agentic-loop:begin region=<name> owner=project
   …
   // @agentic-loop:end region=<name>
   ```

   Then verify mechanically, before showing the user:

   ```bash
   ./scripts/lib/workflow.sh regions .claude/workflows/factory.js   # parses?
   ./scripts/lib/workflow.sh diff .claude/workflows/factory.js \
     "$PLUGIN_ROOT/templates/workflows/factory.js" // \
     "$(./scripts/lib/scaffold.sh region-sums .claude/workflows/factory.js)"
   ```

   A non-empty `conflict` means you touched a plugin region — revert that part
   and redo it as an addendum. Never ship past a conflict.

5. **Show the diff and what it changes at runtime**, then let the user commit.
   A line change alters unattended behavior: it deserves its own commit.

## Adopting an existing fork

A project with a hand-forked workflow (no markers, or a second
`factory-*.js`) rejoins the framework like this:

1. `/agentic-loop:update` first — the plugin may already ship what the fork
   was working around.
2. Diff the fork against the current template and sort every divergence into:
   **redundant** (the plugin now does it — drop it), **project** (genuinely
   yours — carry it over into an addendum or an `owner=project` region), or
   **drift** (the fork's copy of plugin text, stale or altered — discard it,
   the current region supersedes it).
3. Rebuild on the current template + the project pieces from step 2. Do not
   port plugin text across by hand — that is how the stale copy arrives.
4. Delete the fork file so `/factory` resolves to one line again, then
   re-stamp (`scaffold.sh stamp …`) and run `./scripts/doctor.sh`.
5. Tell the user which divergences you dropped as redundant and which plugin
   text the rebuild restored — a fork usually lost something silently, and
   naming it is the point.
