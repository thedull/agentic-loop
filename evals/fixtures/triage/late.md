## Notes / decisions (append-only)

- **attempt** 2026-08-08T10:00:00Z: tried widening the regex — still failed
- **attempt** 2026-08-08T10:05:00Z: tried a different anchor — still failed

- **triage** 2026-08-08T10:00:00Z (attempt 3):
  - reproduce: `./evals/run_eval.sh --suite foo --case foo-001` fails with "expected 3 got 0"
  - localize: `scripts/lib/foo.sh:42` — the accumulator resets inside the loop
  - hypothesis: the counter is declared with `local` inside the while body, so each iteration reinitialises it. Evidence: `scripts/lib/foo.sh:42` declares it inside, and moving the declaration above the loop makes the case pass.
