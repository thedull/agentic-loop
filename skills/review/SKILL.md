---
name: review
description: >-
  Factory review stage: claim the oldest built spec, run a blind fresh-context
  review (security, optimization, test quality) with findings typed by layer,
  apply a bounded revision, verify in a real browser when the change has a UI,
  open a PR with an executive summary and a hand-checkable test plan, and log
  the evening digest. Designed to run unattended — one item per invocation,
  loopable.
---

# agentic-loop:review — built branch → PR + digest

You are the review stage of the factory: the gate between an unattended build
and the user's evening review. Nothing merges here — the terminal state is an
OPEN PR plus a digest entry; merging is the human's signal and theirs alone.

## Steps (one item per invocation)

1. **Usage gate.** `scripts/lib/usage_gate.sh check` — on postpone (exit 5),
   log `review postponed until <resets_at local>` to `.agentic/STATUS.md` and
   stop (same rescheduling rules as the build skill).

2. **Bench reconcile.** `scripts/lib/bench.sh reconcile` — a no-op unless
   `.bench.enabled` is set in `.agentic/config.json`; otherwise ensures every
   `pr-open` spec has a fresh, freshness-merged git-worktree checkout under
   the project's bench dir (so you can actually run the app during evening
   review) and removes benches for specs already `done`. Never blocks this
   stage — a per-bench conflict or failure is reported to stderr and
   reconcile moves on to the next.

3. **Claim.** `scripts/lib/tracker.sh claim built reviewing review-loop`; if
   exit 1, log `review idle` and stop.

4. **Blind review.** Delegate to the `loop-reviewer` subagent (fresh context,
   subscription-covered). Payload: ONLY the spec file and the branch diff
   (`git diff main...claude/idea-<slug>`) — never the build stage's reasoning
   (blind-adversary protocol). Brief it to check, evidence-first:
   - **spec fidelity** — does the diff satisfy each SHALL, or did the tests
     encode a misunderstanding?
   - **security** — input validation gaps, injection vectors, authz
     assumptions;
   - **optimization** — inefficient patterns, hidden coupling, resource leaks;
   - **test quality** — tautological tests, over-mocking, assertions on
     implementation details, implemented behavior not covered by the spec;
   - every finding carries `layer: spec|test|impl` and `severity`.
   Run `check_cmd` and the project suite yourself — reviewer claims without a
   non-LLM check are opinions.

5. **Bounded revision — hard cap 2, routed by layer.**
   - `impl` findings → fix on the branch, re-run `check_cmd`.
   - `test` findings → fix/add the test, confirm it FAILS against the
     pre-fix code (Red Gate applies to revisions too), then fix.
   - `spec` findings → append a delta to the spec's Revision log; if the
     delta needs a user decision, mark the item `blocked` with the question
     recorded and stop.
   A second round ONLY if the first materially changed the artifact AND a
   check still fails. After cap: proceed with caveats stated, or `blocked`.

6. **Structural escalation — record, never spend.** If the routing brain's
   Sol triggers fire (material disagreement, known-hard class, tests failing
   post-revision), do NOT call metered tiers unattended: mark
   `needs_escalation` in the spec Notes and surface it in the digest for the
   user's evening decision.

7. **Browser verification (conditional).** Only when the project has a
   runnable web UI AND the spec's acceptance references UI behavior: run the
   app, execute each Given/When/Then step with Playwright (Chromium is
   preinstalled on Claude Code cloud sessions), capture a screenshot per
   scenario into `.agentic/artifacts/<id>/`, and write the manual test steps
   list. Skip entirely for CLI/library changes — this pass is the expensive
   one, spend it only where it observes something.

8. **Preview (conditional, cheapest first).** Screenshots + test steps in the
   PR body are the default preview — sufficient for most evening reviews at
   zero cost. For static/front-end changes in an environment with Artifact
   publishing (Claude Code web/cloud), additionally publish a self-contained
   HTML preview as a private artifact and link it. Heavier options (GitHub
   Pages branch, Codespaces badge, Cloudflare Pages) are project hooks — use
   only if the project already has them configured.

9. **Open the PR.** Push the branch (`git push -u origin claude/idea-<slug>`)
   and open a PR: title = spec title; body = executive summary (what changed
   and why, ≤10 lines), the acceptance checklist with pass/fail, the **test
   plan** (below — mandatory, never omitted), screenshots,
   caveats/assumptions carried from envelopes, and the spec file reference.
   No remote configured → record `pr: local` and note the branch in the
   digest instead.

   ### The test plan (every PR, no exceptions)

   The reviewer ran what it could; the human still has to trust it. The test
   plan is how they check the work in their own hands, so write it for
   someone who has NOT read the diff and does not know the codebase.

   ```markdown
   ## Test plan

   Bench: `cd ../<repo>-benches/<slug>` — branch is merged with `main`
   and set up.   <!-- omit this line when the bench flag is off -->

   **Automated (already run — re-run to confirm):**
   - [ ] `<check_cmd>` → passes (`<n>/<n>`)
   - [ ] `<project suite cmd>` → passes (`<n>/<n>`)

   **By hand — each maps to one acceptance criterion:**
   - [ ] AC1 — Given <state>, when <action>, then <observable outcome>
   - [ ] AC2 — …

   **Edge cases and failure modes worth poking:**
   - [ ] <the thing most likely to break: empty input, offline, concurrent…>

   **Not verified in this environment** (be honest — this is the most
   useful section):
   - [ ] <e.g. real hardware panel, live tmux, a paid API path>
   ```

   Rules that make it worth reading:
   - **One checkbox per acceptance criterion**, in the spec's own
     Given/When/Then words — they were written to be one step from a test,
     so this is a transcription, not an invention.
   - **Every command is copy-pasteable and complete** — real paths, real
     flags, no `<placeholders>` left unfilled and no "run the tests".
   - **State what you could NOT check** and why. A reviewer who says
     everything passed, when a whole class went unexercised, is the failure
     this pipeline exists to prevent. Live-device, paid-API and
     UI-on-real-hardware gaps go here, not into silence.
   - Never write a checkbox you did not either run yourself or genuinely
     need the human to run. Padding the list trains them to skim it.

   **Also drop a copy in the bench** — only when benches are on
   (`jq -r '.bench.enabled // false' .agentic/config.json` is true) and the
   bench exists. The PR body stays canonical; this copy exists because
   hands-on review happens in a terminal in the bench directory, not in a
   browser tab:

   ```bash
   BENCH="$(./scripts/lib/bench.sh list | awk -v s="<slug>" '$1==s {print s}')"
   # write the SAME test-plan text to <bench dir>/TEST-PLAN.md
   ```

   Resolve the bench dir the way `bench.sh` does (config `.bench.dir`, else
   `../<repo>-benches`). Write the identical text — never a summarized or
   re-worded variant, or the two copies drift and neither can be trusted.
   `TEST-PLAN.md` lives in the bench worktree, so it is never committed to
   the branch. If benches are off or the bench is missing, skip this silently.

10. **Advance + digest.** `tracker.sh advance <file> pr-open pr <url>`, then
   append the digest entry to `.agentic/STATUS.md`:
   `pr-open: <id> <title> — <url> | tests: <pass/fail> | caveats: <n> |
   escalation: <yes/no> | plan: <n> checks, <m> need device`

   The **`plan:`** field is the evening triage signal: `<n>` is how many
   by-hand checkboxes the test plan has, `<m>` how many of them need
   something this environment could not provide (real hardware, a paid API,
   a live account) — i.e. the size of the *"not verified in this
   environment"* section. `plan: 6 checks, 0 need device` says skim and
   merge; `plan: 12 checks, 5 need device` says set aside real time at the
   panel. Write `plan: none` only if you genuinely produced no plan, which
   should not happen.

   When observability is enabled, append
   ` | run: <run id>` (from `.agentic/observability/state/run`, or
   `$AGENTIC_RUN_ID` under a headless loop) so the digest line links to its
   tree: `/agentic-loop:config render` visualizes the run. This block is what
   the user reads in the evening. Stop — one item per invocation.

## Unattended rules

- The reviewer never sees the builder's reasoning; the builder never grades
  its own homework (`check_cmd` + fresh-context review are the graders).
- Merging, metered escalation, and spec decisions belong to the human. When
  in doubt: `blocked` + a precise question beats a shipped guess.
