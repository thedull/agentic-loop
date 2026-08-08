---
name: tracker-field-literal-space-parse-gap
description: "_tracker_field's awk matcher requires a literal ASCII space after `key:` (`index($0, key \": \")==1`) — a tab or other whitespace there makes the field silently resolve as absent/empty, which is dangerous for fail-loud fields like `profile:`"
metadata:
  type: project
---

`scripts/lib/tracker.sh`'s `_tracker_field()` (pre-existing helper, shared by
every frontmatter reader including the new `tracker_profile()` from spec
001) matches a key only via `index($0, key ": ")==1` — literal colon +
single ASCII space. Confirmed live: a fixture with `profile:<TAB>hardened`
(tab instead of space) makes `tracker.sh profile <file>` print `standard`
and exit 0 — the intended `hardened` value is silently dropped and treated
as absent, exactly the fail-silent outcome spec 001's acceptance 3 exists to
prevent ("a hardened spec that quietly gets a standard review... manufactures
false assurance").

**Why:** this is a shared parsing primitive, not something spec 001
introduced — but spec 001 is the first field whose whole point is "never
silently default," so it's the first place this latent gap has a real
consequence. A human hand-editing frontmatter (or a script that pastes with
tabs) can trip it with no warning.

**How to apply:** when reviewing any spec that adds fail-loud semantics to a
frontmatter field read through `_tracker_field`, check what happens with a
tab (or other non-space whitespace) after the colon — don't assume "trimmed
via `${raw#...}` in the caller" covers it, because the caller never sees the
value at all in this case; `_tracker_field` returns empty before the
caller's own trim logic runs. 1st strike: spec 001.
