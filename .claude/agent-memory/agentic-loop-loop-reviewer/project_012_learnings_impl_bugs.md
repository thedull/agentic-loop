---
name: project-012-learnings-impl-bugs
description: scripts/lib/learnings.sh (spec 012) has two live bugs no eval case exercises — a sentinel-string collision that silently drops content, and a crash on empty files under this repo's actual bash (3.2)
metadata:
  type: project
---

Confirmed live against `scripts/lib/learnings.sh` on branch
`claude/idea-012-learnings-consolidation` (commit a55e836), by direct
execution, not inspection.

**1. Sentinel collision drops content silently (high).** `learnings_consolidate`
tags each output line internally with the literal string `\000ENT:<i>` or
`\000DUP:<i>` (plain backslash-zero text, not a real NUL byte — `out+=("\000DUP:$found")`
uses regular `"..."` quoting) and later does
`case "$line" in '\000ENT:'*|'\000DUP:'*) ... ; *) printf ...`. Any *passthrough*
line (one that doesn't start with `- `) whose literal content happens to match
one of these patterns collides with the sentinel and is swallowed on emit.
Reproduced: a 7-line fixture containing the literal line `\000ENT:0` between two
entries came out as 6 lines — that exact line vanished, no error, no warning.
No fixture in `evals/fixtures/learnings/` or case in `evals/cases/learnings/`
exercises this.

**2. Empty-file crash (medium-high).** `learnings_consolidate` on a 0-byte file
crashes: `./scripts/lib/learnings.sh: line 50: out[@]: unbound variable`. Cause:
`set -uo pipefail` + referencing `${out[@]}` on a `local -a out=()` that was
never appended to — this repo's actual runtime is GNU bash 3.2.57
(`/usr/bin/env bash` resolves to the macOS-shipped 3.2 on this box; confirmed
`bash --version` and no other bash on PATH), which treats a truly-empty array
as unset under `set -u` (bash 4+ does not have this issue). The original file
is left intact (crash happens before the truncate-and-rewrite step), but the
command exits 1 and leaves an orphaned `.bak` file. No fixture covers an empty
`LEARNINGS.md`.

**Why this matters:** the spec (`factory/specs/012-learnings-consolidation.md`)
explicitly names mutation-testing acceptance 3 as "the one to mutation-test
hardest" and lists exactly this class of adversarial input in its own Fixtures
note — but the shipped fixtures are all "friendly" (real dated bullets). Neither
bug was caught by `./evals/run_eval.sh --suite learnings` (11/11 pass on
unmutated code). See also [[project_grep_count_mechanical_check_weak]] — same
proof-by-mutation technique surfaces bugs that reading-only review would miss.

**How to apply:** when reviewing any consolidator/rewriter script that uses
plain-string sentinels to mark positions in a rebuilt array, check whether the
sentinel could collide with real input content, and always run it against an
empty input file on the box's *actual* bash — `/usr/bin/env bash` is 3.2 on
stock macOS and its `set -u` + empty-array semantics differ from bash 4/5.
