---
name: shelve
description: >-
  Take a spec out of the factory queue without lying about why — `shelved`
  (deprioritized, reversible) or `superseded` (the outcome landed some other
  way, e.g. a hand-applied hotfix). Reports every downstream spec the removal
  strands and walks you through repairing each broken dependency chain. Use
  when a queued or in-flight spec stopped being worth building, or when its
  work got done outside the loop. Also restores a shelved spec. Interactive.
---

# agentic-loop:shelve — take a spec out of the line

A spec gets claimed, then reality moves: the fix lands by hand, priorities
shift, the idea stops being worth building. Until now the only exits were
`done` (a lie — no PR, no merge) and `blocked` (which means "stuck, help me",
and is what `evals/mine.sh` treats as failure signal). Editing frontmatter by
hand bypasses the tracker seam every skill and workflow relies on.

The real cost is downstream. A dependency is satisfied only by `done`, so a
spec pulled out of the queue any other way strands every dependent
**permanently and invisibly** — they keep showing the same `waits:` column as
a dependency that is merely still in progress.

## The three off-ramps are not interchangeable

| | Means | Dependents |
|---|---|---|
| `blocked` | Stuck; needs a human to answer something. The spec still wants doing. | stall |
| `shelved` | Nobody is doing this now. Reversible. | **stall** — must be rewired |
| `superseded` | The outcome already exists (a hotfix, another spec). | **claimable**, if the citation verifies |

Never route a deprioritization through `blocked`: it poisons the failure
signal the evals mine, and it tells the next reader the spec is waiting on
them.

## Steps

1. **Resolve the target and read its state.** Accept an id (`017`) or a path.

   ```bash
   ./scripts/lib/tracker.sh field <file> status
   ```

2. **Establish which off-ramp.** If the user has not already said, ask once —
   this is the only question that must be asked, because the two states have
   opposite effects on everything downstream:

   > Is this **shelved** (deprioritized — nobody is building it now) or
   > **superseded** (the outcome already landed some other way)?

   Do not infer it from tone. "We don't need it anymore" is genuinely
   ambiguous — it can mean either.

3. **Supersede: get the citation, then report what it proves.**

   ```bash
   ./scripts/lib/tracker.sh supersede <file> <actor> <ref> "<reason>"
   ```

   `<ref>` is a commit-ish (the hotfix's sha, a tag) or a spec id. It is
   **required**, and it is checked rather than believed: a commit must be an
   ancestor of the default branch tip; a spec id must itself be `done`.

   If the command warns that the ref does not verify, say so plainly and do
   not paper over it — the status is recorded, but **dependents stay
   stalled** until the work actually lands. That is the point: marking a spec
   superseded when the work did not land is exactly how dependents once got
   built against a base missing their dependency.

4. **Shelve: expect the mid-stage refusal.**

   ```bash
   ./scripts/lib/tracker.sh shelve <file> <actor> "<reason>"
   ```

   Exit **3** means the spec is `building` or `reviewing` and an unattended
   stage may be writing that very file. Explain that in plain language and
   offer the choice: let the run finish, or shelve anyway. Only re-run with
   `TRACKER_FORCE_LIVE=1` after the user explicitly confirms. Do not reach
   for the override on your own.

   Everything else — `queued`, `specd`, `built`, `pr-open`, `blocked` — is at
   rest between stages and shelves with no override needed.

5. **Report the downstream damage — always, even when it is zero.**

   ```bash
   ./scripts/lib/tracker.sh dependents <id> --transitive
   ```

   Columns are `path<TAB>id<TAB>status<TAB>depth<TAB>via`. Present them
   depth-first (nearest first) so the chain reads as a chain, naming which
   spec pulled each one in. Empty output is a real result — say "nothing
   depends on this" rather than staying silent.

6. **Repair each chain, one spec at a time.** For every dependent, offer
   exactly three options and **take no default**:

   - **drop** — the dependency is no longer needed
     ```bash
     ./scripts/lib/tracker.sh dep-drop <dependent> <shelved-id>
     ```
   - **re-point** — something else delivers it now
     ```bash
     ./scripts/lib/tracker.sh dep-replace <dependent> <shelved-id> <new-id>
     ```
   - **shelve it too** — the whole branch of work is off
     ```bash
     ./scripts/lib/tracker.sh shelve <dependent> <actor> "cascades from <id>"
     ```

   Never hand-edit `depends_on`; these commands exist so the edit is
   recorded and observable. Never pick for the user — a wrong auto-rewire is
   silent, and the next thing that reads it will believe it.

   After a supersede whose citation **did** verify, dependents are already
   claimable and usually need no rewire at all. Say that instead of walking
   the user through a list of non-problems.

7. **Close with the resulting state, not the state you started from.**

   ```bash
   ./scripts/lib/tracker.sh report
   ```

   Point at the `stalled:` column: it names dependencies that can never clear
   on their own. `waits:` alone is ordinary progress. If any `stalled:`
   remains, name it and say it is still waiting on a decision.

8. **Leftover artifacts — report, and ask before touching anything public.**
   Read `branch` and `pr` from the spec (they survive a shelve untouched, on
   purpose, so a restore is exact).

   - **Open PR** — say it is still open and ask whether to close it.
     Closing a PR is public and needs explicit confirmation; never run
     `gh pr close` unprompted, and never as part of an unattended loop.
   - **Branch** — leave it. It costs nothing and a restore needs it.
   - **Bench** — nothing to do. `bench.sh reconcile` retires benches for
     shelved and superseded specs on the next factory iteration.
   - **Build worktree** — if one is left from a forced mid-build shelve,
     offer to remove it only when it is clean.

## Restoring

```bash
./scripts/lib/tracker.sh restore <file> <actor>
```

Returns the spec to whatever status it held when shelved — including back
into `pr-open` with its branch and PR intact. Refuses if the spec is not
shelved, or if it has no `shelved_from` (a hand-edited file): guessing where a
spec belongs is worse than refusing, since a wrong guess silently reinserts it
at the wrong stage.

After restoring, re-check the chains you rewired in step 6 — dropping a
dependency is not undone by a restore, and the user may want it back.

## Rules

- Never route a deprioritization through `blocked`, and never through `done`.
- Never set `shelved`/`superseded` with `tracker.sh advance`; it refuses, and
  the refusal is protecting the bookkeeping `restore` depends on.
- Never supersede without a real citation to justify it.
- Never rewire a dependent the user did not choose to rewire.
- Never close a PR without explicit confirmation.
- If `advance` fails during a factory stage because the spec became
  `shelved`, that is a human pulling it out mid-run. Stop and report — do not
  retry, and do not force past it.
