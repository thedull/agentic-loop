## Notes / decisions (append-only)

- **triage** 2026-08-08T10:00:00Z (attempt 1):
  - localize: `scripts/lib/foo.sh:42` — the accumulator resets inside the loop
  - hypothesis: the counter is declared with `local` inside the while body, so each iteration reinitialises it. Evidence: `scripts/lib/foo.sh:42` declares it inside, and moving the declaration above the loop makes the case pass.
