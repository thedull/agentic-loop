# Roadmap — the centralized bootstrap

Vision (owner, 2026-07-19): **agentic-loop is the first layer for every new
project**, whatever its kind. `init` interviews once and instantiates the
right shape — the loop machinery is the supporting layer, never the core of
the project's CLAUDE.md.

## Today (v0.6)

- Project-first CLAUDE.md: greenfield projects get a 3-question identity
  interview and the `templates/CLAUDE-project.md` skeleton; brownfield
  projects (criterion: `CLAUDE.md` exists) keep their file untouched and
  gain only an `## Operating policy` block importing `LOOP_POLICY.md`.
- Project types wired into init: software-interviewed (interactive loop),
  software-unattended (factory), media (minimal + hand-off to the
  premiere-bridge plugin's `new-video`), other (minimal, kind recorded in
  Domain notes).
- First domain pack in the wild: **premiere-bridge** (layer 2: Premiere MCP
  engine + editing pipeline; layer 3: per-video folders under
  `~/Videos/Premiere/` via `new-video`). Field report:
  `docs/field-reports/2026-07-19-premiere-bridge.md`.

## The audit→insights loop (core to the vision)

Propagating principles is half the job; the other half is **auditing how
projects actually operate and feeding that back**. Today: the
`observability` flag captures every operation to `.agentic/` event logs and
renders run trees. Deferred piece: an **insights pass** — a periodic skill
(or report mode) that mines those logs across runs/projects for tier-usage
patterns (where quota actually goes), verification-failure hotspots,
escalation-trigger frequency, and loop-shape smells — so the loops and the
development process itself get streamlined from evidence, not vibes.

## Deferred (build when a real project of that kind shows up)

- **Per-type template packs** beyond media: research (question → sources →
  cited synthesis state files), commercial pitch decks (audience/offer
  interview → outline → design system), technical documentation
  (source-of-truth inventory → doc tree → freshness checks). Each pack =
  a `templates/packs/<kind>/` dir + an init branch, following the
  premiere-bridge precedent: the pack owns domain scaffolding, init owns
  identity + policy.
- **Unattended bootstrap**: `init` runnable headless with a prefilled
  answers file (factory-style), for scripted project creation.
- **Type registry**: packs self-describe (name, interview questions,
  scaffold recipe) so third-party plugins can register kinds instead of
  hardcoding the init matrix.

## Design rules that hold across all of it

1. CLAUDE.md belongs to the project; policy arrives by import.
2. Brownfield is sacred: never restructure an existing CLAUDE.md.
3. Domain scaffolding lives in domain plugins (premiere-bridge model);
   init only detects/hands off.
