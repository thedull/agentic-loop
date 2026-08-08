---
name: project-require-key-mock-bypass
description: require_key() in scripts/lib/common.sh short-circuits to success whenever MOCK_RESPONSE_FILE is set, before checking the named var — breaks any spec's blanket "every case sets MOCK_RESPONSE_FILE" eval guidance for missing-credential acceptance criteria
metadata:
  type: project
---

`require_key()` at `scripts/lib/common.sh:57-58` is:
```
require_key() {
  [[ -n "${MOCK_RESPONSE_FILE:-}" ]] && return 0
  ...
}
```
It returns success unconditionally whenever `MOCK_RESPONSE_FILE` is non-empty,
*before* checking whether the named credential var is actually set.

**Why this matters:** any spec whose acceptance criteria include a
"missing-credential fails loudly" behavior (e.g. spec 017's acceptance 6 for
`call_sol.sh --via openrouter`) cannot be exercised by a `kind: shim` eval
case that sets `MOCK_RESPONSE_FILE` — the check_cmd notes' common blanket
guidance ("every case is `kind: shim` with `MOCK_RESPONSE_FILE`, so no case
spends money") is actually wrong for that one acceptance. The credential-check
case must omit `mock_response` in its JSON (so `MOCK_RESPONSE_FILE` is unset)
to actually reach the `require_key` check — this is still safe (no network
call happens, since `require_key` exits before curl), just contradicts the
"every case" phrasing if taken literally.

**How to apply:** when reviewing a spec that adds a new `require_key`-gated
credential path and proposes testing it via the `kind: shim` harness, check
whether the check_cmd notes acknowledge this exception. If they say "every
case sets MOCK_RESPONSE_FILE" without carving out the credential-check case,
flag it — a builder following that guidance literally will either skip the
test or write one that passes vacuously regardless of whether the real
credential gate works. Two strikes: first hit was spec 017
(`factory/specs/017-sol-via-openrouter.md` acceptance 6 vs the check_cmd
notes at line 67). Watch for a second occurrence before treating this as a
must-flag pattern rather than a one-off.
