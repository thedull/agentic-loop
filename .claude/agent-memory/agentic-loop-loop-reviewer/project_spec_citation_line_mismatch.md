---
name: spec-citation-line-mismatch
description: Specs sometimes cite a file:line range as evidence for a described behavior, but the cited lines implement a different sub-block than the one described — always open the exact range and check which branch/condition it sits inside.
metadata:
  type: project
---

Spec 019 acceptance 3's third bullet says: "This mirrors the existing Ollama
gate at `scripts/doctor.sh:40-61`, which warns when the server does not
respond rather than failing the run." Reading `scripts/doctor.sh:40-61`
directly shows that range is the *model-pulled / size-class* check, which
only executes inside the branch where the Ollama server DID respond
(`if curl ... http://localhost:11434/api/tags`, doctor.sh:36). The actual
"warns when the server does not respond" behavior is the `else` branch at
doctor.sh:62-64 (`warn "ollama installed but server not responding..."`),
outside the cited range.

**Why:** a citation that names the wrong sub-block can mislead a builder
about which existing code pattern to copy — they may model the new check
after the size-parsing logic instead of the actual unreachable-warn pattern,
or waste time reconciling text that "should" be there but isn't.

**How to apply:** per the standing checklist item 3 ("open every `file:line`
the spec cites, confirm the cited line says what the spec claims"), don't
just confirm the file exists — confirm the *specific claim* attached to the
citation (warns-on-X, fails-on-Y) is literally what those exact lines do, not
a nearby or overlapping block. 1st strike: spec 019.
