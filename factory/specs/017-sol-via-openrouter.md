---
id: 017
title: Fund Sol through OpenRouter as an alternate transport
status: specd
profile: standard
created: 2026-08-08
depends_on: 004
claimed_by:
branch:
pr:
---

# Spec 017 — Fund Sol through OpenRouter as an alternate transport

## Brief (the delegation contract)

- **objective**: let the same Sol adversary/reviser call be funded from `OPENROUTER_API_KEY` instead of `OPENAI_API_KEY`, reusing the identical prompts and envelope, so the choice of transport is a billing decision rather than a behavioural one.
- **user_intent_verbatim**: "(§6 item 4) Add an OpenRouter transport to call_sol.sh... a `--via` flag (or equivalent) that reuses the identical adversary/reviser prompts and envelope, so the same Sol call can be funded from OPENROUTER_API_KEY instead of OPENAI_API_KEY, with the batch variant available for unattended stages." (2026-08-08). Worker naming settled by owner ruling the same day: `sol/openrouter`.
- **input_paths**: `scripts/call_sol.sh`, `scripts/lib/common.sh`, `templates/.env.example`, `scripts/doctor.sh`, `evals/cases/sol-transport/`, `evals/fixtures/`, `scripts/lib/obs.sh`
- **boundaries_non_goals**:
  - Does NOT change the metered-tier policy. OpenRouter is metered too, so `templates/LOOP_POLICY.md:198-201` applies unchanged — no unattended Sol calls on either transport, and no acceptance here weakens that.
  - **Reconciling the verbatim intent, which asks for more than this spec delivers.** The quoted request says batch should be "available for unattended stages." Making batch *available* is in scope; making any Sol call *unattended* is not, and cannot be until the metered rule is re-grounded on quota (`docs/codex-subscription.md` §6 item 5, unbuilt, and deliberately not a dependency of this spec). This spec ships the transport; it leaves the policy exactly where it found it. Stated here so the gap is a decision rather than an oversight.
  - Does NOT change the adversary or reviser system prompts, the `--mode` / `--effort` surface, or the envelope schema. Callers (`evals/judge.sh:56`, every stage) must not need editing.
  - Does NOT select `:batch` automatically, ever. See acceptance 5 — batch is not reliably cheaper.
  - Does NOT remove or deprecate the direct OpenAI transport. Both remain supported.
  - Does NOT change `obs.sh`. The chosen worker name is designed to need no change there.
- **output_spec**: an explicit transport selector on `call_sol.sh` that routes the same brief to either `api.openai.com` or `openrouter.ai`, emitting a worker of `sol` or `sol/openrouter` respectively, with cost taken from whichever figure the chosen provider actually reports.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. Transport SHALL be explicit and SHALL default to today's behaviour.
   - Given no transport flag, when `call_sol.sh` runs, then it uses the direct OpenAI path and behaves exactly as it does today, including its worker name `sol`.
   - Given an explicit selector naming OpenRouter, when it runs, then the request goes to OpenRouter using `OPENROUTER_API_KEY`.
   - Given a selector value that is neither, when it runs, then it refuses with exit 2 and names the valid values. Transport is never inferred from which keys happen to be present — an absent key is a failure of the requested transport, not a reason to silently use the other one.
2. The worker name SHALL carry the transport without disturbing tier attribution.
   - Given a call via OpenRouter, when the envelope is emitted, then `worker` is `sol/openrouter`.
   - Given that envelope, when `obs_tier_from_worker` classifies it, then the tier is `sol` — the existing `sol*` glob at `scripts/lib/obs.sh:167` already matches, and this spec changes no line of `obs.sh`.
3. Cost SHALL come from the provider that was actually billed.
   - Given a call via OpenRouter, when the envelope is emitted, then `usage.est_cost_usd` is OpenRouter's own reported figure (`.usage.cost`, as `scripts/call_openrouter.sh:79` already reads) rather than a figure computed from the constants at `scripts/call_sol.sh:33-34`.
   - Given OpenRouter reports no cost field, when the envelope is emitted, then `est_cost_usd` is null — not zero, and not a fallback computed from the OpenAI price table, which would attribute a number to a source that did not report it (`scripts/lib/obs.sh:18-19`).
   - Given a direct OpenAI call, when the envelope is emitted, then cost is computed as it is today.
4. Prompts, modes and effort SHALL be transport-invariant.
   - Given the same brief and `--mode`/`--effort` on both transports, when each runs, then the system prompt and task prompt sent are byte-identical, and the envelope schema is the same.
   - Given `--effort ultra`, when the transport is OpenRouter, then the call SHALL refuse with exit 2 naming the direct transport as the way to get it. It SHALL NOT silently downgrade, because a silent downgrade makes the flag a lie, and it SHALL NOT emulate multi-agent client-side.
   - Refusal is not one option among two: `--effort ultra` sets a `multi_agent` field plus an `OpenAI-Beta: responses_multi_agent=v1` header on the Responses API (`scripts/call_sol.sh:100-105`), and the OpenRouter chat/completions body this repo builds carries no reasoning or effort field of any kind (`scripts/call_openrouter.sh:53-59`). There is no equivalent setting to apply.
5. `:batch` SHALL be opt-in, OpenRouter-only, and SHALL never be selected automatically.
   - Given no explicit batch request, when a call runs, then the non-batch model id is used.
   - Given batch is requested explicitly on the OpenRouter transport, when the call runs, then the `:batch` model id is used and the worker name still resolves to tier `sol`.
   - Given batch is requested on the direct OpenAI transport, when the call runs, then it refuses with exit 2. `:batch` is an OpenRouter model-id suffix; OpenAI's own batch discount is a separate asynchronous `/v1/batches` endpoint with a different request lifecycle, and building that is explicitly out of scope.
   - Rationale recorded because it is counter-intuitive: batch is *not* reliably a discount. On 2026-08-07 `z-ai/glm-5.2:batch` was priced above its own non-batch variant. Anything that reaches for `:batch` automatically would sometimes pay more for worse latency.
6. A missing credential SHALL fail loudly on the transport that needs it.
   - Given the OpenRouter transport with no `OPENROUTER_API_KEY`, when it runs, then it exits 2 with a message naming that variable — not `OPENAI_API_KEY`.
   - Given the direct transport with no `OPENAI_API_KEY`, when it runs, then today's behaviour is unchanged.
7. `doctor.sh` SHALL report which Sol transports are available.
   - Given `./.env` with one, both, or neither key, when `doctor.sh` runs, then it states which Sol transports can be used, rather than reporting only that `call_sol.sh` is unavailable as it does today at `scripts/doctor.sh:76-77`.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite sol-transport
```

**Build order (spec 004 acceptance 7).** New suite of its own. Write the suite
and its cases first, see them genuinely fail (exit 1), then implement. As with
every spec in this queue, this command exits 0 on the untouched tree until spec
004 adds the zero-case guard; `depends_on: 004` is what prevents this spec being
claimed before that is true.

Cases are `kind: shim` with `MOCK_RESPONSE_FILE`, so no case spends money — the
existing `shim-012-openrouter-mock-cost` case is the pattern. Fixtures needed: an
OpenRouter response carrying `.usage.cost`, one omitting it (acceptance 3's
null), an OpenAI-shaped response, and an error response from each provider.
Acceptance 4 is best tested by capturing the assembled prompt on both transports
and diffing them.

**Acceptance 6 is the exception and must not use a mock.** `require_key` returns
success unconditionally when `MOCK_RESPONSE_FILE` is set
(`scripts/lib/common.sh:58`) — it is a deliberate test seam so mocked runs need
no credentials. A missing-credential case written the usual way therefore cannot
fail even if the credential gate is deleted. That case SHALL run with the mock
unset and the environment scrubbed of the key, and it SHALL be mutation-tested by
removing the `require_key` call and confirming it fails.

Mutation-test acceptance 3's null branch: substitute a computed cost for the
missing one and confirm a case fails. That substitution is the exact failure the
honest-nulls rule exists to prevent, and it would otherwise pass a naive
"is there a number" check.

## Notes / decisions (append-only)

- **Worker name `sol/openrouter`** (owner ruling 2026-08-08). Chosen over a
  separate transport field because `obs_tier_from_worker`'s `sol*` glob already
  matches it, so the expensive tier stays correctly attributed with no change to
  the observability plane at all. The alternative that looked "consistent" —
  naming it `openrouter/openai/gpt-5.6-sol` like the bulk shim does — would have
  classified the single most expensive call in the system as bulk tier, silently
  understating Sol in every per-tier spend report.
- **Transport is never inferred from key presence** (acceptance 1). Inferring it
  would mean a project that adds an OpenRouter key for bulk work silently
  changes where its Sol calls are billed. Explicit selection keeps a billing
  decision a decision.

## Revision log (deltas only — never regenerate this spec)

- 2026-08-08 spec: ADDED from `docs/codex-subscription.md` §6 item 4, after §7.1 found `openai/gpt-5.6-sol` on OpenRouter at the same list price the shim already hardcodes.
- 2026-08-08 grill: SETTLED the worker name as `sol/openrouter` (owner ruling), chosen to preserve tier attribution without touching `obs.sh`.
- 2026-08-08 spec-review: MODIFIED acceptance 5 — `:batch` is now OpenRouter-only with an explicit refusal on the direct transport. The gate found `:batch` is a model-id suffix OpenRouter exposes, while OpenAI's batch discount is a separate async `/v1/batches` lifecycle; three incompatible readings were reachable from the original text.
- 2026-08-08 spec-review: MODIFIED acceptance 4 — `--effort ultra` on OpenRouter now refuses outright. "Applies the equivalent setting" was a false choice: no equivalent exists, and the phrasing invited a client-side multi-agent emulation nobody asked for.
- 2026-08-08 spec-review: ADDED the acceptance-6 mock carve-out. The check-command guidance said every case uses `MOCK_RESPONSE_FILE`, which `scripts/lib/common.sh:58` makes a credential test incapable of ever failing.
- 2026-08-08 spec-review: ADDED a boundary reconciling the verbatim intent's "available for unattended stages" with the no-unattended-metered-calls rule this spec does not touch.
- 2026-08-08 spec-check: MODIFIED input_paths — an acceptance named a path the Brief never declared. Found by `scripts/lib/spec_check.sh` on its first run against the real queue, which is the defect class spec 014 exists to catch.
