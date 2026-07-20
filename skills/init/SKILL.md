---
name: init
description: >-
  Bootstrap any project with the agentic-loop layer: a project-first CLAUDE.md
  (greenfield projects get a short identity interview; existing CLAUDE.md files
  are preserved and only gain a policy import), the orchestrator policy
  (LOOP_POLICY.md), worker shim scripts, run-state directory and per-project
  README. Asks the project type (software interviewed/unattended, media, other)
  and scaffolds accordingly. Use for every new project, or to add the loop to
  an existing one.
---

# agentic-loop:init — bootstrap a project

The everyday project bootstrap. Its product is a **project-first** setup: the
project's CLAUDE.md is about the project (problem, solution, constraints);
the loop policy is a supporting layer that loads via an `@LOOP_POLICY.md`
import. The plugin root is two levels up from this skill's base directory:

```bash
PLUGIN_ROOT="$(cd "<this skill's base directory>/../.." && pwd)"
```

## Steps

1. **Detect green/brownfield.** The criterion is `CLAUDE.md` in the target
   directory:
   - **exists → brownfield.** The project already states its identity —
     NEVER restructure or interview about it. You will only append the
     policy block in step 4b.
   - **absent → greenfield.** You will interview (step 3) and write the
     project-first skeleton in step 4a.

   Also safety-check the rest: if `scripts/`, `.agentic/` or
   `LOOP_POLICY.md` already exist, list what would be overwritten and ask
   before proceeding. Never clobber silently.

2. **Project type** (ask, or take from invocation args; drives what gets
   scaffolded):

   | Type | Scaffold |
   |---|---|
   | `software — interviewed` | interactive loop: everything EXCEPT the factory pieces (no `factory/`, no `.claude/workflows/factory.js`, no statusline mirror; delete the "The factory" section from the project's LOOP_POLICY.md copy) |
   | `software — unattended/loop` | everything, and apply step 7b (statusline usage-gate mirror) without asking |
   | `media` | minimal: LOOP_POLICY.md, `.agentic/`, LEARNINGS.md, AGENTIC_LOOP.md — no factory, no shim scripts unless asked. If the **premiere-bridge** plugin is installed, offer to run its `new-video` skill for the video folder itself (that skill owns the media layout); otherwise mention it exists. |
   | `other` (research, pitch deck, technical docs, …) | minimal, same as media minus the premiere-bridge pointer; record the kind in the CLAUDE.md `## Domain notes` as a seed for future per-type packs (see `docs/roadmap.md`) |

3. **Greenfield identity interview** (skip entirely for brownfield). One
   question at a time, three max, then confirm your summary:
   1. What is this project, in a sentence?
   2. What problem does it solve, and for whom?
   3. Success criteria or hard constraints?

4. **CLAUDE.md**
   - **4a greenfield:** copy `$PLUGIN_ROOT/templates/CLAUDE-project.md` →
     `CLAUDE.md` and fill the `{{…}}` placeholders from the interview.
     Leave `## Domain notes` empty (or seed the project kind for `other`).
   - **4b brownfield:** append to the existing `CLAUDE.md`, verbatim
     structure untouched above it:

     ```markdown

     ## Operating policy

     This project runs on the agentic-loop discipline — model tiering,
     worker envelopes, structural escalation, file-based coordination.
     Full policy loads below; runbook in `AGENTIC_LOOP.md`.

     @LOOP_POLICY.md
     ```

     Show the user the appended diff.
   - Either way: copy `$PLUGIN_ROOT/templates/LOOP_POLICY.md` →
     `LOOP_POLICY.md` (apply the type-specific deletion from step 2 for
     interviewed-software mode).
   - **Import gotcha:** the first session in the project shows a ONE-TIME
     approval dialog for `@LOOP_POLICY.md` — tell the user to accept it
     (declining blocks imports for the project permanently).

5. **Copy the machinery, from `$PLUGIN_ROOT`** (respect the type matrix in
   step 2; `# factory` lines only for unattended-software):
   ```bash
   mkdir -p scripts/lib .agentic/artifacts .claude
   mkdir -p factory/specs .claude/workflows        # factory
   cp -R "$PLUGIN_ROOT/scripts/." scripts/
   cp "$PLUGIN_ROOT/templates/.env.example" .env.example
   cp "$PLUGIN_ROOT/templates/LEARNINGS.md" LEARNINGS.md
   cp "$PLUGIN_ROOT/templates/PROJECT_README.md" AGENTIC_LOOP.md
   cp -R "$PLUGIN_ROOT/templates/agentic-state/." .agentic/
   cp "$PLUGIN_ROOT/templates/factory-spec.md" factory/spec-template.md          # factory
   cp "$PLUGIN_ROOT/templates/statusline-usage.sh" scripts/statusline-usage.sh
   cp "$PLUGIN_ROOT/templates/workflows/factory.js" .claude/workflows/factory.js # factory
   chmod +x scripts/*.sh scripts/lib/*.sh
   ```
   (media/other minimal scaffold: skip `scripts/` and factory lines; still
   copy LEARNINGS.md, AGENTIC_LOOP.md, `.agentic/`.)

6. **.gitignore**: append the lines from
   `$PLUGIN_ROOT/templates/gitignore-snippet` if not already present
   (`.env` and `.agentic/` must be ignored). If the project has no
   `.gitignore`, create one from the snippet.

7. **Do NOT copy any secrets.** Only `.env.example` is copied; the user
   fills `.env` themselves.

7a. **Optional hardening** — mention (don't apply unasked): the spawn-budget
   PreToolUse hook in `$PLUGIN_ROOT/templates/hooks-spawn-guard.json` can be
   merged into the project's `.claude/settings.json`.

7b. **Factory setup** (unattended-software: apply; others: mention only):
   the usage gate needs the statusline mirror — add to
   `.claude/settings.json`:
   ```json
   {"statusLine": {"type": "command", "command": "scripts/statusline-usage.sh"}}
   ```
   `factory/specs/` is COMMITTED (it is the coordination bus between
   sessions), unlike `.agentic/`. Point the user at `docs/factory.md` in the
   plugin root for the day-mode run recipe.

8. **Finish**: for software types run `./scripts/doctor.sh` and show its
   output; point the user at `AGENTIC_LOOP.md` for the remaining checklist
   (fill `.env`, verify subscription login, dry-run one loop). Mention the
   opt-ins once, without enabling anything: `/agentic-loop:config
   observability on` records every operation to a local event log and
   renders run trees (`docs/observability.md`), and `/agentic-loop:config`
   lists the other default-off flags (minimize, grill, guards, summarize).

The four native subagents (`loop-planner`, `loop-worker-cheap`,
`loop-consolidator`, `loop-reviewer`) ship with the plugin itself and are
available in every project where the plugin is enabled — nothing to copy.
