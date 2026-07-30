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
   it exits 1 nothing is claimable: either the queue is empty, or every
   `specd` item is waiting on `depends_on` (the claim's stderr says which,
   and `tracker.sh report` shows `waits: <ids>` per item). Append
   `build idle: no claimable specd items` to `.agentic/STATUS.md` and stop —
   dep-waiting specs become claimable on their own once you merge their
   dependencies; never build one by hand around the gate.

   On a successful claim, tag the stage:
   `scripts/observe.sh context set --phase build --spec-id <claimed file>` —
   every event this run emits now carries the spec (silent no-op when
   observability is off). **Every stop from here on** — advance, blocked,
   vacuous check — ends with `scripts/observe.sh context clear`.

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
   measured failure. If the `minimize` flag is enabled
   (`jq -r '.minimize.enabled // false' .agentic/config.json`), add one
   boundary to every code-writing brief: "minimize mode: walk the
   minimization ladder (need it at all? → reuse codebase → stdlib → native →
   installed dep → one line → minimum code); never trim validation, error
   handling, or security". Validate every returned envelope: check `status`,
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
   append `built: <id> <title> (<branch>)` to `.agentic/STATUS.md`, run
   `scripts/observe.sh context clear`, remove the worktree if your platform
   requires, and stop. One spec per invocation — the loop cadence, not this
   skill, decides throughput.

   If `advance` fails saying the spec is `shelved` or `superseded`, a human
   took it out of the queue while you were building. **Stop and report** —
   do not retry, and never force past it. Say what you built and on which
   branch so the work is findable; the shelve was a deliberate decision and
   overriding it would erase that decision silently.

## Unattended rules

- `needs_input` from any worker, or any question only the user can answer →
  `blocked`, questions recorded in the spec's Notes, next item NOT started
  (the loop will claim it next invocation).
- Never call metered escalation tiers (`call_sol.sh`, `call_fable.sh`)
  unattended — record `needs_escalation` in the spec Notes for the evening
  review instead. The human confirms all metered spend.
- Never write outside the worktree except: the spec file (status/Notes/
  Revision log) and `.agentic/STATUS.md`.
