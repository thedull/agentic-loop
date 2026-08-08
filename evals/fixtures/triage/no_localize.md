## Notes / decisions (append-only)

- **triage** 2026-08-08T10:00:00Z (attempt 1):
  - reproduce: `./evals/run_eval.sh --suite foo --case foo-001` fails with "expected 3 got 0"
  - hypothesis: the counter is declared with `local` inside the while body, so each iteration reinitialises it. Evidence: `scripts/lib/foo.sh:42` declares it inside, and moving the declaration above the loop makes the case pass.
