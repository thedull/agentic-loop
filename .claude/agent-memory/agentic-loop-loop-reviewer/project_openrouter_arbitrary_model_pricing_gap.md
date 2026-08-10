---
name: project_openrouter_arbitrary_model_pricing_gap
description: call_openrouter.sh accepts arbitrary/unlisted model ids, not just the kimi|minimax|mimo aliases — any spec that requires a per-model committed price table must address the unpriced-model case (RESOLVED for spec 018, see below)
metadata:
  type: project
---

**RESOLVED 2026-08-10**: spec 018 (preflight-cost-estimate) shipped acceptance
7 naming exactly this gap and `preflight_price()`/`preflight_gate()` in
`scripts/lib/common.sh:264-379` implement it correctly — an unpriced model
`return 1`s from `preflight_price` and the gate refuses with exit 7, verified
live against `--model kimi` (`moonshotai/kimi-k2`, genuinely unpriced) with
mocks and keys unset. The three current openrouter aliases (kimi, minimax,
mimo) all now refuse on real calls until spec 019 repoints two of them at
priced generation-3 ids — an intentional, documented consequence, not a bug.

`scripts/call_openrouter.sh:38-43` resolves `--model` through a 3-entry alias
table (kimi/minimax/mimo) but falls through `*) MODEL="$MODEL_ARG"` for any
other string — callers can pass any full OpenRouter model id, not just the
three aliases.

**Why:** spec 018 (preflight-cost-estimate) requires "multiply by the
resolved model's price" from "a committed table, not the network" (boundary
3), but its acceptances never address what happens when the resolved model
isn't in that table — which is always possible for openrouter given the
open-ended `*)` case. A gate that silently prices an unknown model at $0 (or
fails open) would let the exact call this feature exists to protect against
through ungated.

**How to apply:** when reviewing any spec that adds per-model pricing,
gating, or rate-limiting keyed off `call_openrouter.sh`'s resolved model,
check whether the acceptance criteria name a fallback for an
unlisted/unpriced model id. If they don't, that's a real missing-edge-case
finding, not speculation — the shim's `*)` fallthrough is architecture, not
guesswork.
