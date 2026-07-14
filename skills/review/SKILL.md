---
name: review
description: >-
  Factory review stage: claim the oldest built spec, run a blind fresh-context
  review (security, optimization, test quality) with findings typed by layer,
  apply a bounded revision, verify in a real browser when the change has a UI,
  open a PR with an executive summary and test steps, and log the evening
  digest. Designed to run unattended — one item per invocation, loopable.
---

# agentic-loop:review — built branch → PR + digest

You are the review stage of the factory: the gate between an unattended build
and the user's evening review. Nothing merges here — the terminal state is an
OPEN PR plus a digest entry; merging is the human's signal and theirs alone.

## Steps (one item per invocation)

1. **Usage gate.** `scripts/lib/usage_gate.sh check` — on postpone (exit 5),
   log `review postponed until <resets_at local>` to `.agentic/STATUS.md` and
   stop (same rescheduling rules as the build skill).

2. **Claim.** `scripts/lib/tracker.sh claim built reviewing review-loop`; if
   exit 1, log `review idle` and stop.

3. **Blind review.** Delegate to the `loop-reviewer` subagent (fresh context,
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

4. **Bounded revision — hard cap 2, routed by layer.**
   - `impl` findings → fix on the branch, re-run `check_cmd`.
   - `test` findings → fix/add the test, confirm it FAILS against the
     pre-fix code (Red Gate applies to revisions too), then fix.
   - `spec` findings → append a delta to the spec's Revision log; if the
     delta needs a user decision, mark the item `blocked` with the question
     recorded and stop.
   A second round ONLY if the first materially changed the artifact AND a
   check still fails. After cap: proceed with caveats stated, or `blocked`.

5. **Structural escalation — record, never spend.** If the routing brain's
   Sol triggers fire (material disagreement, known-hard class, tests failing
   post-revision), do NOT call metered tiers unattended: mark
   `needs_escalation` in the spec Notes and surface it in the digest for the
   user's evening decision.

6. **Browser verification (conditional).** Only when the project has a
   runnable web UI AND the spec's acceptance references UI behavior: run the
   app, execute each Given/When/Then step with Playwright (Chromium is
   preinstalled on Claude Code cloud sessions), capture a screenshot per
   scenario into `.agentic/artifacts/<id>/`, and write the manual test steps
   list. Skip entirely for CLI/library changes — this pass is the expensive
   one, spend it only where it observes something.

7. **Preview (conditional, cheapest first).** Screenshots + test steps in the
   PR body are the default preview — sufficient for most evening reviews at
   zero cost. For static/front-end changes in an environment with Artifact
   publishing (Claude Code web/cloud), additionally publish a self-contained
   HTML preview as a private artifact and link it. Heavier options (GitHub
   Pages branch, Codespaces badge, Cloudflare Pages) are project hooks — use
   only if the project already has them configured.

8. **Open the PR.** Push the branch (`git push -u origin claude/idea-<slug>`)
   and open a PR: title = spec title; body = executive summary (what changed
   and why, ≤10 lines), the acceptance checklist with pass/fail, manual test
   steps, screenshots, caveats/assumptions carried from envelopes, and the
   spec file reference. No remote configured → record `pr: local` and note
   the branch in the digest instead.

9. **Advance + digest.** `tracker.sh advance <file> pr-open pr <url>`, then
   append the digest entry to `.agentic/STATUS.md`:
   `pr-open: <id> <title> — <url> | tests: <pass/fail> | caveats: <n> |
   escalation: <yes/no>`. This block is what the user reads in the evening.
   Stop — one item per invocation.

## Unattended rules

- The reviewer never sees the builder's reasoning; the builder never grades
  its own homework (`check_cmd` + fresh-context review are the graders).
- Merging, metered escalation, and spec decisions belong to the human. When
  in doubt: `blocked` + a precise question beats a shipped guess.
