---
name: project_jq_nonempty_check_misses_zerowidth_unicode
description: jq's test("\\S") (oniguruma \S) treats format-category zero-width Unicode chars (ZWSP, BOM, word joiner, soft hyphen, ZWNJ, ZWJ) as non-whitespace, so a "non-empty string" gate built on it can be satisfied with invisible content
metadata:
  type: project
---

Confirmed live against `scripts/lib/validate_envelope.jq`'s `searched`
emptiness check (`(($f.searched // "") | test("\\S") | not)`, added by spec
016). Oniguruma's `\S`/`\s` correctly treats ASCII whitespace, NBSP (U+00A0),
ideographic space (U+3000), and line/paragraph separators (U+2028/U+2029) as
whitespace — those are rejected. But format-category (`Cf`) invisible
characters are NOT matched by `\s`, so they read as "non-empty":
`searched: "​"` (zero-width space), `"﻿"` (BOM), `"⁠"` (word
joiner), `"­"` (soft hyphen), `"‌"`/`"‍"` (ZWNJ/ZWJ) all pass
validation (`exit 0`) despite carrying no visible content — verified by piping
each through `jq -e -f scripts/lib/validate_envelope.jq`.

**How to apply:** any future spec gating on "non-empty string" via a jq
`test("\\S")` (or similar regex-whitespace) check against attacker-influenced
(model-generated) JSON should be treated as narrowly bypassable. Not currently
exploited by any real model observed in this project, and no eval case covers
it — flag as a gap when reviewing specs 1st strike (this one, spec 016), not
yet a 2-strikes pattern.
