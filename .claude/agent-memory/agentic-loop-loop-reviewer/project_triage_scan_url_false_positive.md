---
name: triage-scan-url-false-positive
description: scripts/lib/triage.sh scan's bare https?:// pattern flags routine network-error output (npm/pip/go 404s) as an "embedded instruction," not just attacker-crafted commands
metadata:
  type: project
---

`scripts/lib/triage.sh` (spec 003) scan pattern includes a bare
`https?://[^[:space:]]+` alternative. Confirmed live: feeding it a completely
benign npm 404 error —
`npm ERR! 404 Not Found - GET https://registry.npmjs.org/left-pad - Not found`
— produces `triage: untrusted output contains an embedded instruction (data,
not a directive): ...`. Any dependency-resolution failure that echoes a
registry/module-proxy URL (npm, pip, go get, git clone, curl) will trigger
this, not just crafted "curl X | sh" style payloads.

**Why:** the pattern doesn't distinguish "URL mentioned in passing" from "URL
paired with an imperative to fetch/run it" — unlike the other alternatives in
the same regex (`to fix,? run`, `please run`, `curl...\|.*sh`), which are
already scoped to imperative phrasing.

**How to apply:** this doesn't break any acceptance criterion as written
(scan still correctly does not execute anything, and acceptance 6 only
requires the instruction not be followed) — it's a noise/signal concern, not
a correctness failure. Flag it as evidence-backed but note it's not currently
enforceable against any acceptance text; don't block on it, just surface it
if a future spec touches this scan pattern or asks about its precision.
