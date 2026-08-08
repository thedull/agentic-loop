---
name: project-headless-agent-needs-live-flag
description: headless-agent eval cases (the only kind that exercises a real subagent's live behavior) unconditionally skip unless run_eval.sh gets --live; a spec's check_cmd that omits --live can never genuinely fail/pass on agent-behavioral acceptances
metadata:
  type: project
---

`evals/run_eval.sh:88-95` — `kind: headless-agent` cases skip (not fail) unless
`--live` is passed: confirmed live by running the existing `reviewer` suite
bare — `./evals/run_eval.sh --suite reviewer` → `[skip]
reviewer-040-seeded-sql-injection (headless-agent — run with --live)`,
`0 pass, 0 fail, 1 skipped`, exit 0. Skips never fail a run
(`run_eval.sh:215`, `[[ $FAIL -eq 0 ]] || exit 1`).

Separately, the `headless-agent` sandbox is a bare `mktemp -d`
(`run_eval.sh:64`) with no mechanism to pre-seed files (e.g.
`.agentic/config.json` for a `guards:` flag toggle) — the case-file schema
(`evals/README.md:39-49`) has no field for it either.

**Why:** any spec whose acceptances are about a *subagent's actual runtime
behavior* (not a script's deterministic output) can only be mechanically
verified via `headless-agent` + `--live`. If the spec's own `check_cmd`
string omits `--live`, those acceptances are structurally unenforceable by
the stated Red Gate — the case can only ever skip, contradicting any
build-order instruction to "see it genuinely fail (exit 1)" first. If a
spec additionally requires toggling a config flag (e.g. `guards: false`)
inside that live run, the harness currently has no seeding mechanism for it
at all, regardless of `--live`.

**How to apply:** when a spec's `input_paths` includes an `agents/*.md` file
and the acceptances describe what the agent's *output* must contain/do
(not just a static schema fixture), check whether `check_cmd` includes
`--live`. If not, and if any acceptance needs environment/config seeding
inside the agent's sandboxed run, flag both gaps. 1st strike: spec 007
(`factory/specs/007-review-severity-and-blockers.md`, acceptances 1/3/4/6).
Related: [[project_primary_objective_unenforced_by_checkcmd]] (same root
class — Brief-level behavioral objective with no fixture path) and
[[project_spec_gate_checkcmd]].
