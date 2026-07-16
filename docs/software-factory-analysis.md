# Software Factory: Research Notes and Design Rationale

This is the citable research companion for the `agentic-loop` plugin's factory feature — three skills (`/agentic-loop:spec`, `/agentic-loop:build`, `/agentic-loop:review`) that turn a morning list of ideas into evening pull requests. It documents the evidence trail: what inspired the shape, what already exists natively in Claude Code, where spec-driven development spends its tokens, which parts of a more rigorous adversarial methodology were worth keeping, and where the factory's design deliberately departs from the workflow that inspired it. Nothing here is asserted without a source; see §7.

## 1. The inspiration

The factory feature is inspired by a workflow Alex Finn posted on 2026-07-13 ([x.com/AlexFinn](https://x.com/AlexFinn), tweet id `2076752798532931758`): hand a batch of ideas to a coding agent in the morning, let it work unattended all day, come back to open pull requests in the evening.

The workflow decomposes into three stages plus two human touchpoints:

1. **`/spec "idea"`** — interactive, run in the morning. Interrogates the user until the idea is fully understood, then writes a detailed spec as a status-tracked issue in an external PM tool (Linear).
2. **`/build` loop** — a separate, unattended session. Polls the tracker for spec'd issues, builds them, advances their status.
3. **`/review` loop** — another separate, unattended session. Picks up built issues, runs a security and optimization review, tests the result **in its own browser** (test steps, screenshots), opens a pull request, and deploys it to a Vercel test sandbox.
4. A chat notification (Slack) delivers the PR, the testing steps, an executive summary, and the sandbox link.
5. The human reviews and reacts with a rocket emoji; the loop merges the PR on that signal.

Structurally, this is a three-stage pipelined factory decoupled through a status-tracked queue, with stage-specialized loops, browser-based verification, and a human-in-the-loop merge gate. It matches the broader "software factory" / continuous-agent pattern already visible in the community (e.g., [continuous-claude](https://github.com/AnandChowdhary/continuous-claude)), with two choices that are specific to Finn's setup rather than inherent to the pattern: an external PM tool as the coordination bus, and a chat emoji as the merge protocol. The load-bearing observation is that only **two** steps in the whole loop require a human: idea intake at the start, and the merge signal at the end. Everything between is unattended.

## 2. Loop taxonomy

Claude Code (as of July 2026) ships several distinct mechanisms for making an agent do more than one turn of work. They differ in what triggers the next iteration and what stops it — a distinction that matters because the factory composes several of them.

| Loop type | Iteration trigger | Termination | Feature (status) |
|---|---|---|---|
| Turn-based | Each human prompt | Human judgment | Ordinary session (official) |
| Goal loop | Haiku evaluator judges condition each turn | Condition met; own turn/time bound | `/goal`, v2.1.139+ (official; works in `-p`) |
| Time/interval | Fixed cron or self-paced 1m–1h (`ScheduleWakeup`) | Esc / self-stop / 7-day expiry; survives via `--resume` or `/bg` | `/loop` + `CronCreate` (official) |
| Scheduled/cloud (Routine) | Cron (min. 1h) / API `/fire` / GitHub PR-release events; fresh cloud session per fire, no prompts | Per-firing; daily caps; draws subscription | Routines, `/schedule` (official, research preview) |
| Desktop scheduled task | Local schedule, min. 1 min, desktop notification, worktree toggle | Per-firing | Desktop app (official) |
| Proactive/event-driven | Pushed events: PR CI/review comments (`/autofix-pr`), Channels | Unsubscribe | Auto-fix PRs + Channels (official) |
| Ralph loop | Shell `while` re-feeds a prompt file | External check-cmd only | Community pattern; this repo's `run_headless.sh` is the gated version |
| Dynamic Workflow | Deterministic JS (`agent()`/`pipeline()`, up to 16 concurrent), saveable to `.claude/workflows/`, re-runnable as `/<name>` | Script completes | Workflow tool, v2.1.154+ (official) |

Finn's `/build` and `/review` loops are time/interval loops; the whole system composes interval loops with event gates. Two field pitfalls are worth naming explicitly, because they're the failure modes a factory needs to design against, not just be aware of:

- **Unbounded loops are an open-ended cost surface** — reports of $400+ overnight bills exist from loops left running without a budget or turn cap.
- **A worker must never grade its own homework, and green status is not the same as success.** A loop that builds, tests, and judges its own output with the same context and the same incentives will converge on plausible-looking failure as readily as on correct output.

**Billing correction.** It's tempting to assume headless (`-p`, unattended) runs are metered differently from interactive ones. They aren't — billing follows the **auth method**, not headless-ness. Plain `claude -p` running under OAuth still draws against the subscription (Max plan, etc.); only `--bare` forces API-key metering. Routines likewise draw against the subscription rather than metered API spend. This refines both `run_headless.sh`'s existing billing warning and HANDOFF.md §10, which had treated headless billing policy as unconfirmed.

## 3. Is it out-of-the-box?

Not as a composed whole, but every piece is. Claude Code (July 2026) natively ships loops, Routines, Workflows, auto-fix PRs, per-agent model tiering, worktree isolation, and browser automation via Playwright/Chromium — everything the tweet's architecture calls for is a first-party primitive. What does not exist is a "software factory" feature that wires them together: no shipped template composes spec-intake, build-loop, review-loop, and merge-gate into one pipeline.

The honest framing, confirmed against the official docs: **all official primitives, wired together yourself.** Building the factory is therefore an integration exercise, not a request for missing platform capability — which is also why the natural place to build it is a plugin rather than a request upstream.

## 4. Spec-driven development: where the tokens go

Finn's `/spec` stage — interrogate until understood, write a detailed spec, gate on that spec before building — is a specific instance of spec-driven development (SDD), a pattern with its own literature and its own known cost profile. Three implementations bracket the design space.

**GitHub's SpecKit** is the heavyweight end. Marmelab measured SpecKit producing **8 files and roughly 1,300 lines for a trivial feature** ([marmelab.com, 2025-11-12](https://marmelab.com/blog/2025/11/12/spec-driven-development-waterfall-strikes-back.html)) — constitution, spec, plan, research, data-model, contracts, tasks, and more, with fixed ceremony regardless of task size (a point GitHub's own maintainers concede in [discussion #1536](https://github.com/github/spec-kit/discussions/1536)). Every phase template re-loads 50–60 lines of extension-hook boilerplate; the `/plan` phase fans out into research tasks; each downstream phase re-reads the growing artifact corpus rather than a stable summary. It is a waterfall front-loading approach with no empirical feedback signal until the very end — SDD spent front-loading tokens on artifacts that a two-line change doesn't need.

**OpenSpec** ([github.com/Fission-AI/OpenSpec](https://github.com/Fission-AI/OpenSpec)) takes a delta model instead: changes are expressed as ADDED/MODIFIED/REMOVED deltas against a small, persistent spec corpus rather than regenerated documents. A secondhand benchmark puts this at roughly half the tokens of SpecKit — about 4x cheaper for comparable work — because a revision touches only what changed rather than the whole artifact stack.

**Matt Pocock's skills** ([github.com/mattpocock/skills](https://github.com/mattpocock/skills)) are the lightweight pole. Two are directly relevant: `grilling`, a one-question-at-a-time interrogation protocol where the agent **greps the codebase instead of asking** whenever the answer is discoverable, escalating only genuine *decisions* to the human, closed by an explicit confirmation gate; and `to-spec`, which synthesizes a single spec file with **no re-interrogation** and no file paths or code pasted into prose. ADRs are written only when a decision is hard to reverse, surprising, and represents a real trade-off — not by default. Context is explicitly capped at roughly 120k tokens (the "smart zone"), past which the agent is instructed to summarize rather than keep accumulating.

The factory's spec stage adopts a blend of the last two, mapped onto the repo's existing 6-field brief format rather than any new schema:

- **One spec file per idea, always** — no constitution, research, data-model, or contracts files, ever.
- The existing 6-field brief plus two additions: **`acceptance`**, written as RFC-2119 SHALL statements with Given/When/Then scenarios (one step removed from an executable test), and **`check_cmd`**, a machine-checkable done-condition. This is the single highest-leverage token saver in the whole pipeline: it lets the build and review stages run one command instead of re-reading spec prose to decide if something is finished.
- **Adaptive depth**: `effort_budget` is triaged first — one seam, reversible? A small idea gets one confirmation question and a brief emitted directly. A large idea gets full grilling, with clarification questions capped and an ADR note written only when Pocock's three-part test (hard to reverse, surprising, real trade-off) holds.
- Revisions are always deltas that patch the existing spec file — never full regeneration.

## 5. VSDD, selectively adopted

VSDD ("Verified Spec-Driven Development," [gist.github.com/dollspace-gay](https://gist.github.com/dollspace-gay/d8d3bc3ecf4188df049d7a4726bb2a00)) is a more elaborate methodology: spec-driven development plus test-driven development plus an adversarial verification-driven-development (VDD) layer, run as a sequential gate chain — spec crystallization (behavioral contracts, edge-case catalog, provable-properties catalog, purity-boundary map) → an adversarial **spec review gate** → tests-first with a **Red Gate** (every test must fail before implementation begins) → adversarial refinement using fresh-context, cross-family, negative-prompted review → **typed feedback routing** (a spec flaw routes back to the spec, a test flaw to the tests, an implementation flaw to a refactor) → optional formal hardening (proofs, fuzzing, mutation testing) → a "hallucination-based" convergence criterion. VSDD's own documentation calls it "high-ceremony by design."

Four ideas were cheap enough, and valuable enough, to adopt directly:

1. **Spec review gate** — a fast, fresh-context reviewer pass on the spec itself (not the code) before build starts: ambiguity, missing edge cases, implicit assumptions, contradictions. This attacks the largest documented failure class directly — HANDOFF.md §5 already cites the MAST finding that roughly 79% of multi-agent failures are spec/coordination failures — at the cost of one subscription-covered review pass, run in the morning while the human is still present to resolve findings interactively.
2. **Red Gate** — when the build stage generates tests and a `check_cmd`, verify they fail before any implementation exists. This is mechanical (run a command), costs zero LLM tokens, and kills tautological done-conditions — the "worker grading its own homework" failure pattern, caught at the test level rather than trusted after the fact.
3. **Test-quality review dimensions** — the reviewer explicitly checks for tautological tests, over-mocking, assertions on implementation details rather than behavior, and implemented behavior that isn't in the spec. This is free: it's prompt text added to an existing review skill, not a new pass.
4. **Typed feedback routing** — reviewer findings carry a `layer: spec|test|impl` tag so the bounded revision round patches the right artifact (a spec delta, an added failing test, or a refactor) instead of a blind full re-generation.

Two pieces of VSDD were rejected, both with a specific reason rooted in this repo's own prior evidence:

- **Unbounded convergence** ("iterate until the adversary hallucinates flaws") directly contradicts the repo's evidence-backed hard revision cap of 2 — self-refine gains concentrate in the first one to two rounds, and longer loops measurably degrade output and reward-hack the critic (HANDOFF.md §5). The cap stays.
- **Formal verification, fuzzing, mutation testing, and purity-boundary maps** are scoped by VSDD's own documentation to correctness-non-negotiable systems, not general-purpose feature work. These are not in the default pipeline; they're documented as an opt-in **hardened profile** (`profile: hardened`) a spec can request, gated behind the same structural triggers that already justify escalating to a cross-family adversarial reviewer.

## 6. Design deltas from the inspiration

The factory keeps the tweet's architecture stage-for-stage but changes four implementation choices, each for a reason grounded in this repo's existing decisions rather than in disagreement with the source workflow:

| Finn's workflow | Factory's choice | Why |
|---|---|---|
| Linear as the coordination bus | Committed files + git as the state machine, with a documented connector interface for future PM-tool adapters | Matches the repo's evidence-backed files-and-git-as-memory decision (no measured benefit from a memory DB/MCP layer on small projects, per HANDOFF.md §5); zero external dependency, zero MCP schema cost |
| Slack + rocket-emoji reaction as the merge gate | GitHub-native signal (PR approval / comment) as the merge gate | No external chat dependency required; the merge action stays where the PR already lives, and stays human-triggered either way — the design constraint from the source workflow (a human gates every merge) is preserved, not weakened |
| Vercel test sandbox | A subscription-first sandbox ladder: PR screenshots/test steps → Claude Artifacts preview → GitHub-native previews (Codespaces, Pages) → Cloudflare Pages free tier → Vercel/Netlify hobby tier documented last | Deploy-platform dependency is avoidable for most review passes; the ladder defaults to $0 and to primitives already in play (Playwright output, GitHub) before reaching for a separate platform |
| No usage awareness — loops run until stopped or capped externally | Usage-aware self-gating: a statusline mirror writes rate-limit percentages to a local file; every factory skill checks it before claiming new work and postpones past the reset time if over threshold | Unbounded loops are the field's most common documented failure mode ($400+ overnight reports); the factory is designed to postpone rather than burn budget or silently fail |

A fifth, cross-cutting constraint: the factory is designed to run **without metered spend** in its default configuration. Every stage routes through subscription-covered tiers by default; metered API spend (e.g., a cross-family frontier reviewer) is opt-in and reserved for structural triggers, not the default path.

## 7. Sources

- Marmelab, "Spec-Driven Development: Waterfall Strikes Back?" (2025-11-12) — SpecKit file-count/line-count measurement: https://marmelab.com/blog/2025/11/12/spec-driven-development-waterfall-strikes-back.html
- GitHub, `spec-kit` — https://github.com/github/spec-kit, and discussion #1536 on fixed ceremony regardless of task size: https://github.com/github/spec-kit/discussions/1536
- Fission-AI, `OpenSpec` — delta-based spec model: https://github.com/Fission-AI/OpenSpec
- Matt Pocock, `skills` (`grilling`, `to-spec`) — https://github.com/mattpocock/skills
- "VSDD" gist (Verified Spec-Driven Development) — https://gist.github.com/dollspace-gay/d8d3bc3ecf4188df049d7a4726bb2a00
- Geoffrey Huntley, "Ralph" — https://ghuntley.com/ralph/
- Anand Chowdhary, `continuous-claude` — https://github.com/AnandChowdhary/continuous-claude
- Claude Code official docs (code.claude.com): [`/goal`](https://code.claude.com/docs/en/goal.md), [scheduled tasks](https://code.claude.com/docs/en/scheduled-tasks.md), [routines](https://code.claude.com/docs/en/routines.md), [workflows](https://code.claude.com/docs/en/workflows.md), [statusline](https://code.claude.com/docs/en/statusline.md), [errors](https://code.claude.com/docs/en/errors.md), [costs](https://code.claude.com/docs/en/costs.md), [headless](https://code.claude.com/docs/en/headless.md)
- Armin Ronacher, "The Coming Loop" (2026-06-23) — https://lucumr.pocoo.org/2026/6/23/the-coming-loop/
- Addy Osmani, "Loop Engineering" — https://addyosmani.com/blog/loop-engineering/
- Alex Finn, tweet (2026-07-13, id `2076752798532931758`) — https://x.com/AlexFinn

---

*Companion document: `docs/factory.md` carries the implementation guide and walkthrough.*
