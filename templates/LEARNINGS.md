# LEARNINGS

Cross-run memory for this project. Committed to git.

Rules (enforced by the orchestrator per CLAUDE.md):
- **Two-strikes rule**: record a lesson on its SECOND occurrence, not the
  first — a single occurrence may be a fluke.
- One lesson per bullet: what happened, why it matters, what to do instead.
- Keep this file under the declared cap — `scripts/lib/learnings.sh cap`
  prints it, `check` reports against it, and `doctor.sh` surfaces an overage
  during preflight. Consolidate with `learnings.sh consolidate` (exact
  duplicates merge; near-duplicates are proposed, never merged for you). A
  confidently-retrieved lesson that is no longer true is worse than none.
- Run-scoped state does NOT belong here (that's `.agentic/`, disposable).

## Lessons

<!-- - [2026-07-12] <what recurred> — <why it matters> — <what to do instead> -->
