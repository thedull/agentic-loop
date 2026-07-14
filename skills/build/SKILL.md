---
name: build
description: >-
  Factory build stage: claim the oldest reviewed spec from the queue, build it
  on an isolated branch with tier-routed workers under Red Gate discipline
  (tests must fail before implementation), and advance it for review. Designed
  to run unattended — one spec per invocation, loopable via /loop or the
  factory workflow.
---

# agentic-loop:build — spec → built branch

You are the build stage of the factory. You run unattended: the user is not
here to answer questions. A spec that turns out to be under-specified is
marked `blocked` with questions recorded — never guessed through.

## Steps (one spec per invocation)

1. **Usage gate.** Run `scripts/lib/usage_gate.sh check`. On postpone (exit
   5): append one line to `.agentic/STATUS.md` — `build postponed until
   <resets_at as local time>: usage over threshold` — and STOP. If running
   under a dynamic `/loop`, schedule the next wake at that reset time; under
   a fixed `/loop`, end this iteration (later iterations re-check).

2. **Claim.** `scripts/lib/tracker.sh claim specd building build-loop` — if
   it exits 1 the queue is empty: append `build idle: no specd items` to
   `.agentic/STATUS.md` and stop.

3. **Isolate.** From the claimed spec's filename derive `<slug>`; create a
   git worktree on branch `claude/idea-<slug>` (reuse the branch if it exists
   from a prior blocked attempt). All build work happens in that worktree —
   never on the main checkout.

4. **Red Gate.** Write the tests (or fixture/assertion) that `check_cmd`
   runs, translated from the spec's Given/When/Then acceptance — BEFORE any
   implementation. Run `check_cmd`; it MUST fail. If it passes on the
   untouched codebase, the check is vacuous: record that in the spec's
   Revision log, mark the spec `blocked` (`tracker.sh advance <file> blocked`),
   note it in `.agentic/STATUS.md`, and stop — a vacuous check would let an
   empty implementation ship.

5. **Build, tier-routed.** Delegate per the project `CLAUDE.md` routing brain:
   construct the 6-field brief VERBATIM from the spec's Brief section (the
   spec was written to be this brief — do not paraphrase it), route
   mechanical parts to `loop-worker-cheap` (haiku) or `call_ollama.sh`,
   judgment parts to sonnet-tier subagents; escalate one tier only on
   measured failure. Validate every returned envelope: check `status`,
   verify `artifacts[]` exist on disk, carry `key_decisions`/`caveats`
   forward into the spec's Notes.

6. **Green + hygiene.** Run `check_cmd` until it passes (bounded: if it still
   fails after two escalated attempts, mark `blocked` with the failure output
   quoted in the spec's Revision log and stop). Also run the project's
   existing test/lint commands if any — a green `check_cmd` that breaks the
   rest of the suite is not done.

7. **Commit** on the branch with a message referencing the spec id. Do not
   push, do not open a PR — that is the review stage's job, and nothing
   reaches the remote before blind review.

8. **Advance.** `tracker.sh advance <file> built branch claude/idea-<slug>`,
   append `built: <id> <title> (<branch>)` to `.agentic/STATUS.md`, remove the
   worktree if your platform requires, and stop. One spec per invocation —
   the loop cadence, not this skill, decides throughput.

## Unattended rules

- `needs_input` from any worker, or any question only the user can answer →
  `blocked`, questions recorded in the spec's Notes, next item NOT started
  (the loop will claim it next invocation).
- Never call metered escalation tiers (`call_sol.sh`, `call_fable.sh`)
  unattended — record `needs_escalation` in the spec Notes for the evening
  review instead. The human confirms all metered spend.
- Never write outside the worktree except: the spec file (status/Notes/
  Revision log) and `.agentic/STATUS.md`.
