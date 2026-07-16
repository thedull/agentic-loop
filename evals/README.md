# evals/ — the plugin's own eval harness

Bespoke and dependency-light (bash + jq, same as the rest of the repo). The
things under test — subagent prompt files, bash shims, state machines — don't
fit RAGAS/DeepEval/promptfoo; the repo already owns the schema oracle
(`scripts/lib/validate_envelope.jq`), the judge transport (the shims,
including cross-family judges), and the case format (the 6-field brief). See
`docs/observability-evals-analysis.md` §3 for the full rationale.

## Running

```bash
./evals/run_eval.sh                 # FREE: bash-unit + mocked shims. Always $0.
./evals/run_eval.sh --live          # also headless-agent cases: spawns
                                    # `claude -p` — draws subscription quota /
                                    # metered billing, same caveats as
                                    # run_headless.sh. Run manually, never on
                                    # a timer.
./evals/run_eval.sh --suite envelope
./evals/run_eval.sh --case shim-010-ollama-mock-ok
./evals/run_eval.sh --judge openrouter   # judge tier override
```

Results land in `evals/results/results-<ts>.jsonl` (gitignored). Exit 1 on
any failure; skips (missing --live, no judge tier) never fail a run.

## Cost expectations

| Suite | Kind | Cost |
|---|---|---|
| envelope, shim | bash-unit / mocked | $0, seconds |
| planner-routing, consolidator, reviewer | headless-agent (--live) | a few `claude -p` calls on your subscription/metered auth; judged cases add 1 free (ollama) or ~$0.01 (openrouter) judge call each |
| full --live run | everything | well under $0.50 metered |

## Case format

```json
{
  "id": "suite-NNN-slug",
  "target": "what is under test",
  "kind": "bash-unit | shim | headless-agent",
  "cmd": "…",                      // bash-unit: runs in a sandbox; $PLUGIN_ROOT and $FIXTURES are set
  "shim": "call_ollama.sh",        // shim: which script
  "mock_response": "fixtures/x.json", // shim: canned API response (MOCK_RESPONSE_FILE seam; no keys needed)
  "agent": "agentic-loop:loop-planner", // headless-agent
  "input": { "brief": { "objective": "…", "user_intent_verbatim": "…",
             "input_paths": [], "boundaries_non_goals": [],
             "output_spec": "…", "effort_budget": "…" } },
  "checks": [
    { "type": "envelope_valid" },
    { "type": "jq", "expr": ".status == \"ok\"" },
    { "type": "exit_code", "equals": 0 },            // or "nonzero": true
    { "type": "artifact_exists", "paths_from": ".artifacts" },
    { "type": "must_find", "strings": ["injection"] },
    { "type": "tier_expect", "path": ".result.subtasks[].tier", "allowed": ["ollama","haiku"] },
    { "type": "judge", "rubric": "rubrics/reviewer-findings.md", "min_score": 3 }
  ],
  "provenance": { "source": "hand|mined", "run_id": null, "date": "…" }
}
```

## Judge protocol (deterministic first, judge last)

Planted-defect detection is `must_find`/`jq` — never a judge. `judge.sh` only
grades free-form quality on anchored 1–4 rubrics (`rubrics/`), with bias
guards baked in: blind provenance, 8000-char candidate cap + "do not reward
length", cross-family default (ollama free → OpenRouter kimi; Sol is
explicit-only via `--tier sol`), and `--compare A B` runs both orderings and
reports `agree` so position bias shows up as "inconclusive" instead of a fake
verdict.

## The flywheel

`./evals/mine.sh` scans the observability event log
(`.agentic/observability/events-*.jsonl`) for failures — error/blocked shim
calls, caveated results, exhausted headless runs, blocked tracker transitions
— and drafts pre-filled case files into `cases/_inbox/`. Mining proposes,
humans curate: give a draft real checks and move it into a suite. Failures
observed today become tomorrow's regression suite.

## Adding a case

1. Pick the cheapest kind that exercises the behavior (bash-unit > shim-mocked
   > headless-agent).
2. Encode what SHOULD happen as deterministic checks; add a `judge` check only
   for quality grading.
3. `./evals/run_eval.sh --case <id>` until green; commit the case (results
   stay out of git).
