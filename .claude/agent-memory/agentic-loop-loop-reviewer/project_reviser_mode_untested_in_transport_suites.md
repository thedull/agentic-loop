---
name: project-reviser-mode-untested-in-transport-suites
description: eval suites for call_sol.sh flags/transports repeatedly exercise --mode adversary only; --mode reviser is never run through the harness even when the acceptance text says "modes" (plural) must hold
metadata:
  type: project
---

Spec 017's `evals/cases/sol-transport/` (22 cases) never passes `--mode
reviser` anywhere — `grep -rn reviser evals/cases/sol-transport/*.json`
returns nothing. Acceptance 4 says "Prompts, modes and effort SHALL be
transport-invariant" (plural "modes"), but only case 008's byte-identical
check and everything else run in the default adversary mode.

**Why this matters:** manual verification showed the actual behavior IS
correct for reviser mode too (byte-identical system/task prompts across
`--via openai` vs `--via openrouter` with `--mode reviser`) — so this is a
coverage gap in the suite, not a functional bug, this time. But it means a
regression that broke reviser-mode-specific behavior (e.g. a future change
that special-cases MODE inside the transport-selection branch) would not be
caught by this suite.

**How to apply:** when reviewing a spec whose acceptance criteria says
"modes" or "prompts and modes" must hold some invariant, check that at least
one case in the suite actually passes `--mode reviser` (or whatever the
non-default mode is called), not just the default. 1st strike: spec 017.
