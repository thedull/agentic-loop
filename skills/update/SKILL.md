---
name: update
description: >-
  Refresh a project's plugin-owned scaffold (scripts/, the factory workflow and
  spec template) from the installed agentic-loop, without touching anything the
  project owns. Reports exactly what changed, asks before overwriting any file
  edited locally, and records a version stamp so the next run knows what it is
  looking at. Use when a project was scaffolded by an older plugin version, when
  doctor.sh reports scaffold drift, or after upgrading the plugin.
---

# agentic-loop:update — refresh the scaffold

`/agentic-loop:init` copies plugin-owned files into a project once. They then
rot silently: two projects scaffolded months apart were both still carrying a
`tracker.sh` from before `depends_on` existed and had never heard of
`bench.sh`. Fixing the plugin does not fix the projects — this skill does.

The plugin root is two levels up from this skill's base directory:

```bash
PLUGIN_ROOT="$(cd "<this skill's base directory>/../.." && pwd)"
```

## The ownership contract (do not violate it)

**Plugin-owned** — enumerated in `scripts/lib/scaffold.sh`'s manifest, and the
only things this skill writes: the shim scripts, `scripts/lib/*`, `doctor.sh`,
`statusline-usage.sh`, `factory/spec-template.md`,
`.claude/workflows/factory.js`.

**User-owned** — never written here, no exceptions: `CLAUDE.md`,
`LOOP_POLICY.md`, `LEARNINGS.md`, `.env`, `.agentic/`, `factory/specs/`, and
every file the project itself authored. `LOOP_POLICY.md` in particular is
*supposed* to diverge — init deletes its factory section for
interviewed-software projects.

`scripts/` is a **shared** directory, not a plugin-owned one: projects keep
their own scripts beside ours (`scripts/build-app.sh`, `scripts/assets/*.mjs`
were both seen in the field). Copy the manifest's files individually. Never
`rm -rf scripts/`.

## Steps

1. **Announce the source, loudly.** Print the plugin root you resolved and its
   version (`jq -r .version "$PLUGIN_ROOT/.claude-plugin/plugin.json"`). This
   is not decoration: a user whose installed cache is older than the plugin
   they have been developing will otherwise "update" a project *backwards* and
   never know. If the root is an install cache
   (`~/.claude/plugins/cache/…`), say so and note that
   `claude plugin update agentic-loop` refreshes it; if it is a working
   checkout (`--plugin-dir`), say that instead.

2. **Establish the project type.** Read it from the stamp
   (`scripts/lib/scaffold.sh version` and the stamp's `project_type`). No
   stamp → infer: `factory/` present → `software-unattended`; `scripts/`
   present without `factory/` → `software-interviewed`; neither →
   `media`/`other`, which scaffold no plugin files at all — say there is
   nothing to update and stop.

3. **Survey the drift.** Run, from the project root:

   ```bash
   "$PLUGIN_ROOT/scripts/lib/scaffold.sh" status "$PLUGIN_ROOT" <type>
   ```

   Each line is `path<TAB>state`:
   - `ok` — identical to the plugin's copy; skip it.
   - `missing` — the plugin ships it and the project lacks it; install it.
   - `stale` — differs from the plugin but still matches its stamp, so nobody
     edited it; replace it.
   - `modified` — differs from its **stamp**. Someone edited this file. Ask.
   - `unverified` — differs from the plugin with no stamp entry to judge by
     (the normal state of a pre-stamping project). Do not guess: resolve it in
     step 4.
   - `kept` — the user already chose to hold their own version on an earlier
     run. Report it, never touch it, never re-ask.

4. **Resolve `unverified` before touching anything.** For each such file:

   ```bash
   "$PLUGIN_ROOT/scripts/lib/scaffold.sh" trace <dest> <source> "$PLUGIN_ROOT"
   ```

   A printed commit means the project's copy is byte-identical to the plugin's
   file at that commit — a clean older copy, not a local edit — so treat it as
   `stale` and say which version it matched. Empty output means it matches no
   release in history: treat it as `modified` and ask. (`trace` needs the
   plugin root to be a git checkout; from a cache install it returns nothing,
   which correctly degrades to asking.)

5. **Show the plan, then ask once.** Print a table — file, state, action
   (install / replace / keep) — with counts. If the project is a git repo and
   any target path already has uncommitted changes, say so: the user may want
   to commit first so the update is reviewable as its own diff. Get
   confirmation before writing. For anything classified `modified`, show the
   diff (`diff <project file> "$PLUGIN_ROOT/<source>"`) and ask per file:
   **keep mine / take the plugin's**. Default to keeping theirs — a local edit
   is evidence of intent, and silently reverting it is the one failure this
   skill must never have.

6. **Apply.** Copy each approved file from `$PLUGIN_ROOT/<source>` to
   `<dest>`, creating parent directories as needed, then
   `chmod +x scripts/*.sh scripts/lib/*.sh`. Copy only manifest files.

7. **Re-stamp, and record every "keep mine".** From the project root:

   ```bash
   "$PLUGIN_ROOT/scripts/lib/scaffold.sh" stamp "$PLUGIN_ROOT" <type> "<source label>"
   "$PLUGIN_ROOT/scripts/lib/scaffold.sh" keep <each file the user chose to keep>
   ```

   The stamp (`scripts/.agentic-scaffold.json`) records the plugin version,
   project type, source, and — for each manifest file — **the checksum of
   what upstream shipped**, not of the project's copy. It is **committed** on
   purpose: it travels with the files it describes, so a fresh clone still
   gets a correct verdict.

   Running `keep` is not optional bookkeeping. Without it a kept file reads
   `modified` on every future run and you would re-ask forever; with it the
   file reads `kept` and is left alone. Skipping either half of this step is
   how a user's deliberate edit eventually gets reverted.

8. **Report what you did NOT touch.** Diff the user-owned templates against
   the project's copies (`templates/LOOP_POLICY.md` vs `LOOP_POLICY.md`,
   `templates/PROJECT_README.md` vs `AGENTIC_LOOP.md`) and, if upstream moved,
   list them as "changed upstream — merge by hand if you want them". Do not
   write them. Name the skills/subagents that ship with the plugin and need no
   copying at all.

9. **Verify.** Run `./scripts/doctor.sh` and show its output; its "scaffold
   version" section should now report a stamp and no drift. Mention any new
   feature the update just delivered that is off by default (e.g. review
   benches — `/agentic-loop:config bench on`), so the user knows it arrived.

## Rules

- Never write a user-owned file. When in doubt about ownership, it is
  user-owned.
- Never revert a local edit without explicit per-file confirmation.
- Never claim a version you did not verify — print what `plugin.json` says.
- Re-running with nothing to do must be a clean no-op that says so.
