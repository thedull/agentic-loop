## Notes / decisions (append-only)

- **triage** 2026-08-08T10:00:00Z (attempt 1):
  - reproduce: `./evals/run_eval.sh --suite foo --case foo-001` fails with "expected 3 got 0"
  - localize: `scripts/lib/foo.sh:42` — the accumulator resets inside the loop
  - evidence: `scripts/lib/foo.sh:42`
