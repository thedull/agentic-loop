---
id: 019
title: Refresh the OpenRouter aliases and detect delisted model ids
status: specd
profile: standard
created: 2026-08-08
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 019 — Refresh the OpenRouter aliases and detect delisted model ids

## Brief (the delegation contract)

- **objective**: point the OpenRouter aliases at the current generation, and make a delisted model id a condition `doctor.sh` reports rather than one a user discovers when a call fails.
- **user_intent_verbatim**: "Refresh the stale OpenRouter aliases... nothing in the repo detects a delisted model id — the mimo defect shipped into every stamped project and no offline test could have caught it, because a dead id is still a well-formed string." (2026-08-08). Network question settled by owner ruling the same day: *"Yes — probe the live catalog, warn on unreachable."*
- **input_paths**: `scripts/call_openrouter.sh`, `scripts/doctor.sh`, `templates/.env.example`, `evals/cases/alias-liveness/`, `evals/fixtures/`
- **boundaries_non_goals**:
  - Does NOT probe the catalog at call time. `call_openrouter.sh` stays a single request; a liveness round-trip in front of every call would add latency and a failure mode to the hot path. Detection belongs in `doctor.sh`, which is a health check nobody is waiting on.
  - Does NOT fail `doctor.sh` on an unreachable network. Offline is a normal state for this repo's users, and an unreachable catalog is unknown, not broken.
  - Does NOT validate arbitrary model ids passed with `--model <full id>`. Only the declared aliases and their `.env` overrides are checked — those are the values this repo ships and is therefore responsible for.
  - Does NOT change alias *names*. `kimi`, `minimax`, `mimo` keep their names; only the ids they resolve to move.
  - Does NOT pin a price. Spec 018 owns pricing; this spec is about existence.
- **output_spec**: aliases resolving to model ids with a catalog context window of at least 1,000,000, and a `doctor.sh` check that resolves every alias against the live OpenRouter catalog and reports each one through doctor's existing `ok`/`warn` helpers (`scripts/doctor.sh:9-11`) — ok when present, warn when absent, and a single warn when liveness could not be established.
- **effort_budget**: small

## Acceptance (behavioral, testable — no implementation details)

1. The shipped aliases SHALL resolve to ids meeting a stated, decidable currency bar.
   - **"Current generation" means a catalog `context_length` of at least 1,000,000.** Stated operationally because the vaguer phrasing was satisfiable by doing nothing: `moonshotai/kimi-k2` and `minimax/minimax-m2` are *stale*, not *dead*, and both still resolve in the catalog today. Mere presence is not the bar; the context window is.
   - Given `kimi` and `minimax`, when they resolve, then each names an id whose catalog `context_length` is >= 1,000,000, and the id, its context length and its verification date are recorded in the Revision log.
   - Given the check for this acceptance, when it runs against a fixture catalog in which an alias resolves to a sub-1M id, then it fails — the case must be capable of failing on today's shipped values.
   - Given `mimo`, when it resolves, then it is unchanged from `xiaomi/mimo-v2.5` — already corrected in 0.14.8, and this spec does not re-litigate it.
2. `doctor.sh` SHALL resolve every alias, including `.env` overrides, and report each one.
   - Given an alias whose id is present in the catalog, when `doctor.sh` runs, then it reports through the existing `ok` helper for that alias.
   - Given an alias whose id is absent from the catalog, when `doctor.sh` runs, then it reports through the existing `warn` helper, naming the alias, the dead id, and the `OPENROUTER_MODEL_*` variable that would override it. No new reporting vocabulary is introduced — `doctor.sh:9-11` already defines `ok`/`warn`/`fail` and eval string matches depend on it.
   - Given `./.env` overriding an alias, when `doctor.sh` runs, then the **override** is the value checked — checking the built-in default while the project uses something else would report on a value nobody calls.
3. An unreachable catalog SHALL be reported as unverifiable, never as ok and never as a failure.
   - Given no network, or a request exceeding a short timeout, when `doctor.sh` runs, then it emits one warning that liveness could not be checked, does not report any alias as ok, and does not fail the overall run.
   - Given a catalog response that is not valid JSON or lacks the expected shape, when `doctor.sh` runs, then it is treated exactly as unreachable.
   - Given a response that is valid JSON of the right shape but contains zero models, when `doctor.sh` runs, then it is ALSO treated as unverifiable — not as three simultaneously-dead aliases, which would read as catastrophic when the likeliest cause is an upstream hiccup.
   - This mirrors the existing Ollama gate, whose not-responding branch warns rather than failing the run (`scripts/doctor.sh:62-64`); the model-presence checks inside the responded branch are at `scripts/doctor.sh:40-61`.
4. The probe SHALL be bounded and SHALL NOT be able to hang a health check.
   - Given a catalog that accepts the connection and never responds, when `doctor.sh` runs, then the probe times out within a documented short bound and acceptance 3's unverifiable path is taken.
   - Given the probe, when `doctor.sh` runs, then it makes at most one catalog request regardless of how many aliases are checked.
5. Liveness checking SHALL NOT require a credential.
   - Given no `OPENROUTER_API_KEY`, when `doctor.sh` runs, then the liveness check still runs — the catalog endpoint is public, and a project without a key still ships aliases that can rot.
6. `call_openrouter.sh` SHALL be unchanged in behaviour apart from the resolved ids.
   - Given any existing invocation, when it runs after this change, then its request shape, envelope, worker name and exit codes are identical to today.
   - Given the existing `shim` suite, when it runs after this change, then all its cases still pass.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite alias-liveness
```

**Build order (spec 004 acceptance 7).** New suite of its own. Write the suite
and its cases first, see them genuinely fail (exit 1), then implement. This
command exits 0 on the untouched tree until spec 004 lands its zero-case guard;
`depends_on: 004` is what stops the spec being claimed before then.

**No eval case may reach the network.** The probe must be injectable — a case
supplies a fixture catalog rather than calling `openrouter.ai`, in the spirit of
`MOCK_RESPONSE_FILE`. Fixtures needed: a catalog containing every alias id, one
missing an alias id, one that is malformed JSON, an empty-but-valid catalog
(acceptance 3's "no models found" case), and a simulated timeout. Acceptance 2's
override case needs a fixture `.env`.

**Acceptance 1 needs its own case and it is the one most likely to be skipped.**
The refresh is the headline objective and nothing above tests it: a fixture
catalog in which `kimi` or `minimax` resolves to a sub-1M-context id must make
the suite fail. Without it the primary deliverable has no Red Gate at all, and
the spec passes while the aliases stay exactly as they are.

Cases are `kind: bash-unit` — the harness has three kinds (`bash-unit`, `shim`,
`headless-agent`) and only `bash-unit` can invoke `doctor.sh` with a sandbox cwd
and a fixture catalog.

Mutation-test acceptance 3 in the awkward direction: make an unreachable catalog
report ok, and confirm a case fails. A liveness check that silently passes when
it could not look is worse than no check, because it converts "unknown" into
"verified" — the same class of defect as writing an estimate where a billed cost
belongs.

## Notes / decisions (append-only)

- **doctor.sh gains its first non-localhost dependency** (owner ruling
  2026-08-08). Accepted deliberately: a delisted id is a well-formed string, so
  no offline test can detect it, and the `mimo` defect proved the class ships
  silently into every stamped project. The alternatives were a committed model
  table (goes stale the same way the alias did — it would have caught `mimo`
  only if somebody had refreshed it, which is the failure being fixed) and an
  opt-in flag (a check nobody runs is a check nobody has). The cost is that
  `doctor.sh` now behaves differently offline, which acceptance 3 makes explicit
  rather than incidental.
- **Aliases rot on a schedule nobody controls.** This spec fixes today's ids and
  adds the detector; it does not claim to prevent recurrence. The detector is
  the durable part — the ids in acceptance 1 will themselves be stale eventually,
  and that is expected rather than a defect.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-08 spec: ADDED. `kimi` points at `moonshotai/kimi-k2` (131k context) and `minimax` at `minimax/minimax-m2` (205k) where the current generation is 1M+; `mimo` was fixed separately in 0.14.8 after resolving to a delisted `xiaomi/mimo-v2`.
- 2026-08-08 grill: SETTLED the network question by owner ruling — probe the live catalog with a short timeout and warn when unreachable, matching the Ollama gate rather than shipping a table that rots the same way.
- 2026-08-08 spec-review: MODIFIED acceptance 1 — "current generation" is now the decidable bar `context_length >= 1,000,000`. The gate found the original wording satisfiable by a no-op, because both shipped ids are still present in the catalog; they are stale, not delisted, and presence was the only thing being asserted.
- 2026-08-08 spec-review: ADDED a required case for acceptance 1. The headline objective had no fixture in the build-order list, so the spec could have passed with the aliases untouched.
- 2026-08-08 spec-review: ADDED the empty-but-valid catalog to acceptance 3's own bullets. It had been stated only in build-order prose that referred back to acceptance 3 as though the rule were already there.
- 2026-08-08 spec-review: MODIFIED the Ollama citation. The not-responding warn is `doctor.sh:62-64`; `:40-61` is the model-presence check inside the branch where the server did respond.
- 2026-08-08 spec-review: MODIFIED the reporting vocabulary to doctor's existing `ok`/`warn` helpers rather than a new present/absent/unverifiable wording, which eval string matches would not have found.
- 2026-08-10 build: VERIFIED acceptance 1 against the live catalog (`https://openrouter.ai/api/v1/models`, 400 models, 2026-08-10) rather than against the doc snapshot. `moonshotai/kimi-k3` context_length **1048576**; `minimax/minimax-m3` context_length **1048576**; both clear the >= 1,000,000 bar. The ids they replace measured 131072 (`kimi-k2`) and 204800 (`minimax-m2`), confirming the spec's claim that they are stale rather than dead. `xiaomi/mimo-v2.5` measured **1050000** — already above the bar, so acceptance 1's "unchanged" and the currency bar agree and mimo needed no change. Eval fixtures are subsets of that real response, so the shapes and numbers in them are not invented.
- 2026-08-10 build: FIXED a test seam that could lie. The fetch log recorded `--max-time` from a separate string while `curl` was invoked independently, so removing the bound from the actual call left case 013 passing — it asserted an intention rather than a fact. Mutation 10 survived on exactly that. The logged line and the executed call are now the same argv array, and the mutation is caught.
- 2026-08-10 build: FIXED the `.env` override lookup. This block runs before doctor's worker-key section sources `./.env`, so `${!OR_VAR}` was empty for a project that had overridden an alias and the check silently reported on the built-in default — the value nobody calls, which is the precise failure acceptance 2's third bullet forbids. It now reads the file directly, the same shape the Ollama gate uses.
- 2026-08-10 build: RECORDED an unresolved interaction with spec 018, outside this spec's `input_paths`. 018 refuses any model with no entry in its committed price table. After this refresh `kimi` and `minimax` resolve to priced ids and call normally, but **`mimo` -> `xiaomi/mimo-v2.5` is still unpriced and therefore still refuses on a real call.** The live catalog gives its price as 0.00000014/0.00000028 per token, i.e. **$0.14 / $0.28 per 1M** (verified 2026-08-10), so the fix is one line in `preflight_price()` in `scripts/lib/common.sh` — a file this spec does not declare, and whose pricing this spec's boundaries explicitly assign to 018. Left for a follow-up rather than taken silently.
