---
name: project-flag-missing-value-crashes-no-envelope
description: call_sol.sh's EXTRA_ARGS flag parser crashes with bash "unbound variable" (exit 1, no JSON envelope) when a value-taking flag is the last arg — violates common.sh's own documented failure contract
metadata:
  type: project
---

`scripts/call_sol.sh`'s hand-rolled flag loop (e.g. line 57:
`--via) VIA="${EXTRA_ARGS[$((i+1))]}"; i=$((i+2)) ;;`) indexes one past the
array under `set -euo pipefail` (line 25). If the flag is the last argument
(`--via` with nothing after it, same for pre-existing `--mode`/`--effort`),
bash's `set -u` raises "unbound variable" and the script exits 1 with a raw
bash error on stderr — no JSON envelope at all.

**Why this matters:** `scripts/lib/common.sh`'s header contract (lines 14-16)
says every call_*.sh script must emit "Non-zero exit + status:\"error\"
envelope on any failure. Nothing else is ever printed to stdout." This crash
breaks that contract. Confirmed live:
```
cat brief.json | MOCK_RESPONSE_FILE=... bash scripts/call_sol.sh --mode adversary --via
# scripts/call_sol.sh: line 57: EXTRA_ARGS[$((i+1))]: unbound variable
# exit=1, no envelope printed
```
The bug is pre-existing (same shape already present for `--mode`/`--effort`
on `main` before spec 017), not introduced by spec 017 — the diff just
extended the same unsafe pattern to the new `--via` flag rather than fixing
it. No spec 017 acceptance covers a missing-value case, so this wasn't a
Red Gate requirement, but it's a real robustness gap in any call_*.sh that
uses this loop shape.

**How to apply:** when reviewing any spec that adds a new value-taking flag
to a call_*.sh shim using this EXTRA_ARGS loop pattern, check whether the
flag is guarded against being the last token (e.g. `${EXTRA_ARGS[$((i+1))]:-}`
with an explicit missing-value refusal). Treat as low severity unless the
spec's acceptance criteria explicitly requires graceful handling of a
missing flag value. 1st strike: spec 017, `scripts/call_sol.sh:55-57`.
