---
id: 018
title: Estimate the cost of a metered shim call before making it
status: specd
profile: standard
created: 2026-08-08
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 018 — Estimate the cost of a metered shim call before making it

## Brief (the delegation contract)

- **objective**: put a number in front of a metered call before it is made, and refuse the call above a threshold unless it is explicitly authorized — turning "the human confirms all metered spend" from prose into a gate.
- **user_intent_verbatim**: "(§6 item 11) Pre-flight cost estimate before a metered shim call, with a confirmation threshold... Estimate tokens, multiply by the resolved model's price, print it, and require confirmation above a threshold." (2026-08-08). Gate-versus-inform settled by owner ruling the same day: *"Gate: refuse above threshold unless explicitly authorized."*
- **input_paths**: `scripts/lib/common.sh`, `scripts/call_sol.sh`, `scripts/call_fable.sh`, `scripts/call_openrouter.sh`, `templates/.env.example`, `evals/cases/preflight-cost/`, `evals/fixtures/`, `scripts/call_ollama.sh`
- **boundaries_non_goals**:
  - Does NOT write an estimate into `usage.est_cost_usd`. That field is reserved for what a provider actually reported; `scripts/lib/obs.sh:17-19` forbids fabricating costs a source did not report, and an estimate written there would be indistinguishable from a billed figure forever after.
  - Does NOT gate the free tiers. `call_ollama.sh` spends nothing and is untouched.
  - Does NOT fetch a live price list at call time. A network round-trip before every call trades the thing being protected (cost) for latency and a new failure mode; prices come from a committed table.
  - Does NOT relax the metered-tier policy. This is an additional refusal, never a permission — nothing here authorizes an unattended metered call.
  - Does NOT attempt exact tokenization. See acceptance 3: an approximation labelled as one is the deliverable.
- **output_spec**: before any metered shim issues its request, an estimated cost is printed to stderr; above a configured threshold the call refuses with a distinct exit code unless explicitly authorized, and no estimate ever reaches the envelope's cost field.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. Every metered shim SHALL print an estimate before issuing its request.
   - Given a call on `call_sol.sh`, `call_fable.sh` or `call_openrouter.sh`, when it runs, then an estimated cost is written to **stderr** before the request is sent.
   - Given any such call, when it completes, then stdout still contains exactly one envelope JSON and nothing else — the stdout contract at `scripts/lib/common.sh:14-16` is unchanged.
   - Given `call_ollama.sh`, when it runs, then no estimate is printed and nothing changes.
2. An estimate SHALL be labelled an estimate and SHALL NEVER be recorded as a cost.
   - Given any call, when the envelope is emitted, then `usage.est_cost_usd` holds only a provider-reported figure or null, exactly as today. No code path writes the pre-flight number there. The rule being honoured is `scripts/lib/obs.sh:17-19` — *"Nulls are honest — never fabricate tokens or costs a source did not report."*
   - Given the printed line, when it is read, then it identifies itself as an estimate and names the model and the price basis it used.
3. The token estimate SHALL be a stated approximation, not a claim of accuracy.
   - Given the assembled prompt from `build_task_prompt` (`scripts/lib/common.sh:138-159`), when tokens are estimated, then a documented deterministic heuristic is used and the method is named in the printed line.
   - Given the same input twice, when estimated twice, then the two estimates are identical — the heuristic is deterministic, so a threshold decision is reproducible.
   - Output tokens cannot be known before the call. The estimate SHALL use a declared assumed output size and SHALL say so, rather than silently estimating input only and understating the total.
   - The assumed output size SHALL vary with the requested effort, not be a single flat number. `--effort ultra` runs parallel subagents and *"token use scales with agent count"* (`scripts/call_sol.sh:20-21`, with `max_concurrent_subagents: 3` at `:103`), so a flat assumption would systematically understate the single most expensive path — precisely the call this gate exists to catch.
4. Above the threshold the call SHALL refuse, and refusal SHALL be distinguishable.
   - Given an estimate at or above the configured threshold and no explicit authorization, when the shim runs, then it does NOT issue the request, emits a `status: "blocked"` envelope naming the estimate and the threshold, and exits with a code distinct from every existing one (2 bad flag, 3 missing tool, 4 schema, 5 transport, 6 refusal).
   - Given an estimate below the threshold, when the shim runs, then the call proceeds normally.
5. Authorization SHALL be explicit and SHALL NOT be inferred.
   - Given an explicit authorization flag or environment variable set by the caller, when the estimate exceeds the threshold, then the call proceeds and the printed line records that it was authorized.
   - Given no such flag, when the estimate exceeds the threshold, then acceptance 4's refusal stands. Authorization is never inferred from a TTY, from an interactive session, or from the absence of a CI variable.
6. The threshold SHALL be configurable with a safe default, and SHALL fail closed on nonsense.
   - Given no configuration, when a shim runs, then a documented default threshold applies.
   - Given a threshold that is absent, negative, or non-numeric, when a shim runs, then it refuses rather than treating the gate as disabled. A broken threshold must not silently mean "no limit".
   - The disable sentinel SHALL be the explicit string `off`, and SHALL NOT be a number. `0` is reserved for its literal meaning — a threshold of zero refuses every metered call — because a numeric sentinel that means the opposite of its literal reading is the kind of overload a tired reader gets backwards.
   - Given the threshold set to `off`, when a shim runs, then the gate does not refuse and the estimate is still printed.
7. An unpriced model SHALL refuse, not default to free.
   - Given a resolved model with no entry in the committed price table, when a shim runs, then it refuses with acceptance 4's exit code and names the missing model. `scripts/call_openrouter.sh:38-43` accepts any model id, not only the three aliases, so the unlisted case is reachable by design and is exactly where a mispriced call is most likely.
   - Given that refusal, when the operator wants to proceed anyway, then acceptance 5's explicit authorization is the way through — an unknown price is a reason to ask, not a reason to stop permanently.
8. Mocked runs SHALL be exempt, by the seam that already exists.
   - Given `MOCK_RESPONSE_FILE` is set, when a shim runs, then the gate does not refuse — mocked runs spend nothing, and this mirrors `require_key`'s existing exemption at `scripts/lib/common.sh:58`.
   - Given the full existing eval suite, when it runs after this change, then all 88 cases still pass.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite preflight-cost
```

**Build order (spec 004 acceptance 7).** New suite of its own. Write the suite
and its cases first, see them genuinely fail (exit 1), then implement. This
command exits 0 on the untouched tree until spec 004 adds the zero-case guard;
`depends_on: 004` is what prevents the spec being claimed before that holds.

**Acceptance 8 makes the mock seam a problem for testing acceptances 4, 5 and 6.**
A gate that is exempt under `MOCK_RESPONSE_FILE` cannot be exercised by an
ordinary `kind: shim` case. Those acceptances need cases that drive the
estimate-and-threshold logic directly with the mock unset and no credential
present, so the refusal happens before any request would be issued — the shim
must decide to refuse *before* it needs a key, and a case asserting that
ordering is worth having on its own.

Mutation-test acceptance 2 hardest: make the pre-flight number flow into
`usage.est_cost_usd` and confirm a case fails. That single substitution would
make every historical cost figure in the event log unreliable, and it would pass
any check that merely asks whether a number is present.

## Notes / decisions (append-only)

- **A gate, not a printout** (owner ruling 2026-08-08). The confirm-before-Sol
  rule exists in seven places as prose with nothing enforcing it; this is the
  first mechanism. Rejected alternatives: inform-only (adds no enforcement, an
  accidental oversized call still ships); gate-only-when-interactive (infers
  intent from TTY detection, and leaves the unattended path — the one nobody is
  watching — ungated); and gate-with-no-escape (a legitimate large review
  becomes a config edit, which ends with the threshold set uselessly high).
- **Estimates and costs are different kinds of number** (acceptance 2, boundary
  1). Keeping them in separate fields is the whole reason this can be built
  without damaging the observability plane. Once an estimate is written where a
  billed figure belongs, no later consumer can tell them apart.
- **Prices come from a committed table, not the network** (boundary 3). It costs
  accuracy — the OpenRouter catalog moved 34% on one model within a single day
  on 2026-08-07 — and buys determinism plus no new failure mode in front of
  every call. The staleness is real and is the accepted trade.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-08 spec: ADDED from `docs/codex-subscription.md` §6 item 11.
- 2026-08-08 grill: SETTLED gate-versus-inform by owner ruling — refuse above threshold unless explicitly authorized, with the mock seam exempt.
- 2026-08-08 spec-review: ADDED acceptance 7 — an unpriced model must refuse. `call_openrouter.sh:38-43` accepts arbitrary model ids, so a gate that defaults an unknown model to zero would be silently bypassed for exactly the unvetted models most likely to be mispriced.
- 2026-08-08 spec-review: MODIFIED acceptance 3 — the assumed output size now varies with effort. A flat assumption understates `--effort ultra`, which scales token use with subagent count (`call_sol.sh:20-21`), i.e. the costliest call the gate is for.
- 2026-08-08 spec-review: MODIFIED acceptance 6 — the disable sentinel is now the explicit string `off`. It was unnamed, and by elimination a builder would have reached for `0`, which also reads literally as "refuse everything".
- 2026-08-08 spec-review: MODIFIED the obs.sh citation from `:18-19` to `:17-19`. Line 17 carries the word "never"; quoting from 18 drops the negation and the prohibition reads as an affirmation.
- 2026-08-08 spec-check: MODIFIED input_paths — an acceptance named a path the Brief never declared. Found by `scripts/lib/spec_check.sh` on its first run against the real queue, which is the defect class spec 014 exists to catch.
- 2026-08-10 build: RECORDED a consequence of acceptance 7 that the spec did not anticipate, because it is a real behaviour change and not a detail. All three current `call_openrouter.sh` aliases resolve to models with no entry in the committed price table — `kimi` → `moonshotai/kimi-k2`, `minimax` → `minimax/minimax-m2`, `mimo` → `xiaomi/mimo-v2.5` — so each now REFUSES on a real (unmocked) call with exit 7. That is acceptance 7 behaving exactly as specified: an unpriced model is a reason to ask, not a reason to bill blind. Mocked eval cases are unaffected (acceptance 8), so the suite does not show it. The prices in the table are the ones `docs/codex-subscription.md` §7.1 actually sourced on 2026-08-07, and the current alias targets are not among them; inventing numbers for them would be the same fabrication the honest-nulls rule forbids. **Spec 019 repoints `kimi` and `minimax` at the 1M-context generation (`moonshotai/kimi-k3`, `minimax/minimax-m3`), both of which ARE priced here, which closes this for two of the three.** Until then the escape is `--authorize-cost`.
- 2026-08-10 build: NOTED that acceptance 8's "all 88 cases still pass" is a stale count — the suite is at 285 passing as of this build. Read as written it would be unsatisfiable; the intent is that the existing suite stays green, which case 028 asserts mechanically for the shim suite and the full sweep confirms overall.
- 2026-08-10 build: RESOLVED an ambiguity in acceptance 6 rather than guessing silently. It says a threshold that is "absent" must refuse, while the preceding clause says "no configuration" gets the default. These are read as two different states: the variable UNSET means no configuration and gets the documented 1.00 default; the variable SET BUT EMPTY is a broken config and refuses. Any other reading makes the two clauses contradict each other.
- 2026-08-10 build: ADDED cases 029 and 030 after mutation testing found two guards nothing could detect. Nothing asserted that the estimated COST includes the assumed output tokens — an input-only estimate priced every effort level identically and understated every call — and nothing sat exactly ON the threshold, so `>=` could be weakened to `>` and the at-threshold call would slip through.
- 2026-08-10 review: FIXED a weak test the blind review proved weak by running it. Case 015 only grepped stderr for the word "threshold" and never compared the printed value to the documented default, so moving `PREFLIGHT_DEFAULT_THRESHOLD_USD` from 1.00 to 9999.00 left the suite fully green. It now asserts `DEFAULT=1.00`, and that exact mutation fails it. A silent change to the safe default is precisely what the case exists to catch.
- 2026-08-10 review: FIXED the token estimate's label and its cross-machine determinism. `${#var}` counts characters under a UTF-8 locale and bytes otherwise, so the line said "chars/4" while often counting bytes, and the same prompt could estimate differently on two machines — making a threshold decision non-reproducible across environments even though acceptance 3's same-input-twice test passed. It is now pinned to bytes with `local LC_ALL=C` and labelled `bytes/4`. Bytes are also the better proxy: a multibyte character is usually more than one token, so counting characters would understate non-ASCII prompts. Case 031 compares a run under `LC_ALL=C` with one under `en_US.UTF-8`.
