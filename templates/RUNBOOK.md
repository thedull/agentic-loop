# Runbook — new project, unattended factory

Copy this file into an empty folder and follow it top to bottom. End state: a
project where you write ideas in the morning, a loop builds and reviews them
unattended all day (subscription-gated, zero metered spend), and you merge
open PRs in the evening with a full observability trail.

Time: ~20 min interactive setup, then mornings ~5 min/idea.

---

## Phase 0 — prerequisites (one-time, this machine)

- [ ] `claude` CLI installed and **logged in on your subscription**: run
      `claude`, type `/login` if prompted. Headless calls fail with
      "OAuth session expired" when this lapses — re-login fixes it.
- [ ] `jq` and `curl` on PATH.
- [ ] The plugin installed (verify: `claude plugin list`):
      ```bash
      claude plugin marketplace add thedull/agentic-loop
      claude plugin install agentic-loop@agentic-loop
      ```
      From a local checkout, point `marketplace add` at the path instead of
      the GitHub slug. Or load it per-session without installing:
      `claude --plugin-dir /path/to/agentic-loop`
- [ ] **No `ANTHROPIC_API_KEY` anywhere** — not exported, not in any `.env`.
      It silently flips your subscription session to metered API billing.
- [ ] Optional but recommended (free local tier + free eval judge):
      `ollama serve` with a **non-thinking** model pulled, e.g.
      `ollama pull gemma4:12b`. Thinking models (qwen3.5:\*) can burn their
      whole output inside `<think>` and return empty results.
- [ ] Optional worker keys if you want them: `FABLE_KEY`, `OPENAI_API_KEY`,
      `OPENROUTER_API_KEY` (metered — the factory never spends them
      unattended; they serve interactive escalation and eval judges).

## Phase 1 — project bootstrap (interactive, in the new folder)

```bash
git init && git commit --allow-empty -m "init"   # factory needs git + worktrees
claude                                           # start a session here
```

In that session:

- [ ] `/agentic-loop:init` — scaffolds scripts/, CLAUDE.md, .env.example,
      `.agentic/`, factory/specs/, the factory workflow, and runs doctor.
- [ ] Copy `.env.example` → `.env`; uncomment the `OLLAMA_MODEL=` line and
      set it to `gemma4:12b` (or your non-thinking model). Add worker keys
      only if you have them — all keys are blank/commented by default.
- [ ] Install the statusline usage mirror (the factory's self-gating depends
      on it) — merge into `.claude/settings.json`:
      `{"statusLine": {"type": "command", "command": "scripts/statusline-usage.sh"}}`
- [ ] Optional: merge `templates/hooks-spawn-guard.json` (plugin root) into
      `.claude/settings.json` — runaway-fan-out backstop.
- [ ] `/agentic-loop:config observability on` — you want the trail for every
      unattended run. Optionally also: `guards on` (reviewer quality gates),
      `minimize on` (smallest-sufficient-diff builds), `grill on` (deeper
      spec interviews).
- [ ] `./scripts/doctor.sh` → fix anything red, rerun until only warnings you
      understand remain.
- [ ] **Make `check_cmd` possible**: an unattended build needs a runnable
      test command from day one. For a fresh repo, set up the minimal
      harness now (e.g. `npm init` + a test runner, or `pytest` + one
      trivial test) and commit it. A spec whose `check_cmd` can't run goes
      straight to `blocked`.

## Phase 2 — seed the queue (interactive, morning, ~5 min/idea)

- [ ] `/agentic-loop:spec "your idea in one sentence"` — answer its
      questions (one at a time; depth adapts to idea size). Repeat per idea.
- [ ] Each spec must end with a **real** `check_cmd` — a command that FAILS
      today and passes when the idea is built. `true` is vacuous and the Red
      Gate will block it.
- [ ] Verify the queue: `./scripts/lib/tracker.sh report` → items in `specd`.

## Phase 3 — unattended run (day)

Start a dedicated session in the project folder (terminal, tmux, or a
backgrounded desktop session) and leave it running:

```
/loop 60m /factory
```

What holds while you're away — by construction, not by promise:

- The **usage gate** checks subscription caps before every claim and
  postpones past the reset instead of burning retries.
- **No metered spend**: Sol/Fable escalation triggers are recorded as
  `needs_escalation` in the spec for your evening decision, never called.
- **Blocked beats guessed**: any question only you can answer stops that
  item (`blocked` + the question in the spec Notes), not the whole loop.
- Terminal state is an **open PR** — nothing merges without you.

Checking in from another terminal (all read-only):

```bash
tail -5 .agentic/STATUS.md                 # the digest so far
./scripts/lib/tracker.sh report            # queue state
./scripts/observe_render.sh --tty          # live tree of the latest run
```

## Phase 4 — evening review (~10 min)

- [ ] Read `.agentic/STATUS.md`: one line per item —
      `pr-open: … | tests: … | caveats: n | escalation: yes/no | run: <id>`.
- [ ] For anything surprising: `./scripts/observe_render.sh --run <id>` and
      open the HTML report — every subagent/shim call with model, tokens,
      duration, status, summary.
- [ ] Merge the PRs you like. For `escalation: yes` items, decide whether a
      metered Sol/Fable pass is worth it and run it interactively.
- [ ] Answer `blocked` specs (the question is in the spec's Notes), set them
      back with `./scripts/lib/tracker.sh advance <file> specd` if they
      should retry tomorrow.
- [ ] `./evals/mine.sh` — drafts eval cases from today's failures into
      `evals/cases/_inbox/`; curate the good ones into real suites.

## Phase 5 — weekly hygiene (~15 min)

- [ ] `./evals/run_eval.sh` (free, $0) — regression-check the machinery.
      Occasionally `--live` (a few subscription calls) to re-baseline agent
      behavior.
- [ ] Recalibrate the cost table in `CLAUDE.md` from observed usage:
      `cat .agentic/observability/events-*.jsonl | jq -s '[.[] | select(.event=="shim_call")] | group_by(.tier) | map({tier: .[0].tier, calls: length, cost: (map(.est_cost_usd // 0) | add)})'`
- [ ] Prune `LEARNINGS.md` (two-strikes rule, ~300-line cap).
- [ ] If you enabled `minimize`/`guards`: compare runs with the flag on vs
      off (`feature_toggle` events mark the switches) before deciding to
      keep them on.

---

## Gotchas (each cost us real debugging time — read once)

| Symptom | Cause / fix |
|---|---|
| A shim call hangs forever | stdin held open by a non-interactive shell — append `< /dev/null` unless piping a JSON brief |
| Worker returns `status: partial`, empty result, thousands of output tokens | thinking-tier Ollama model spent everything in `<think>` — use a non-thinking model |
| Headless agent "writes a plan" instead of executing | `claude -p` landed in plan mode — pass `--permission-mode acceptEdits` |
| Headless agent can't read a file you gave it | path outside its cwd — pass `--add-dir <dir>` |
| Every headless call: "Failed to authenticate: OAuth session expired" | re-run `/login` in any interactive `claude` session |
| Everything suddenly bills dollars | an `ANTHROPIC_API_KEY` leaked into scope — unset it; `doctor.sh` catches this |
| No events in `.agentic/observability/` | observability is opt-in — `/agentic-loop:config observability on` (or `AGENTIC_OBSERVE=1` for one run) |
