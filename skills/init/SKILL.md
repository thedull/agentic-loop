---
name: init
description: >-
  Scaffold the agentic-loop template into the current project directory: copies
  the worker shim scripts, routing-policy CLAUDE.md, .env.example, run-state
  directory and per-project README. Use when the user wants to set up the
  orchestrated multi-model agentic loop in a new or existing project.
---

# agentic-loop:init — scaffold a project

Copy the agentic-loop template into the current project directory. The plugin
root is **two levels up from this skill's base directory** (this file lives at
`<plugin-root>/skills/init/SKILL.md`). Resolve it first:

```bash
PLUGIN_ROOT="$(cd "<this skill's base directory>/../.." && pwd)"
```

## Steps

1. **Safety check.** If the target directory already contains a `scripts/`
   directory, a `CLAUDE.md`, or a `.agentic/` directory, list what would be
   overwritten and ask the user before proceeding. Never clobber silently.

2. **Copy, from `$PLUGIN_ROOT`, into the project:**
   ```bash
   mkdir -p scripts/lib .agentic/artifacts
   cp -R "$PLUGIN_ROOT/scripts/." scripts/
   cp "$PLUGIN_ROOT/templates/.env.example" .env.example
   cp "$PLUGIN_ROOT/templates/LEARNINGS.md" LEARNINGS.md
   cp "$PLUGIN_ROOT/templates/PROJECT_README.md" AGENTIC_LOOP.md
   cp -R "$PLUGIN_ROOT/templates/agentic-state/." .agentic/
   chmod +x scripts/*.sh
   ```

3. **CLAUDE.md**: if the project has no `CLAUDE.md`, copy
   `$PLUGIN_ROOT/templates/CLAUDE.md` as-is. If one exists, append the
   template's content under a `# Agentic Loop` heading instead (show the user
   the diff).

4. **.gitignore**: append the lines from
   `$PLUGIN_ROOT/templates/gitignore-snippet` if not already present
   (`.env` and `.agentic/` must be ignored). If the project has no
   `.gitignore`, create one from the snippet.

5. **Do NOT copy any secrets.** Only `.env.example` is copied; the user fills
   `.env` themselves.

6. **Optional hardening** — mention (don't apply unasked): the spawn-budget
   PreToolUse hook in `$PLUGIN_ROOT/templates/hooks-spawn-guard.json` can be
   merged into the project's `.claude/settings.json`.

7. **Finish** by running `./scripts/doctor.sh` and showing the user its
   output, then point them at `AGENTIC_LOOP.md` for the remaining checklist
   (fill `.env`, verify subscription login, dry-run one loop).

The four native subagents (`loop-planner`, `loop-worker-cheap`,
`loop-consolidator`, `loop-reviewer`) ship with the plugin itself and are
available in every project where the plugin is enabled — nothing to copy.
