---
name: exit-code-4-already-overloaded
description: exit code 4 already means two unrelated things elsewhere in this repo before spec 004 gives run_eval.sh's top-level exit a third meaning — check for this whenever a spec proposes a new exit code.
metadata:
  type: project
---

`scripts/lib/common.sh:90` (`validate_envelope()`) already `exit 4`s when a
worker's envelope fails schema validation — this function is piped into from
`finalize_envelope()` (common.sh:203-236), which every one of the four
`scripts/call_*.sh` shims calls as their last step. Confirmed live:
`call_ollama.sh` ends with `finalize_envelope "$MODEL_TEXT" ...` piping to
`validate_envelope`, and the script has `set -euo pipefail` (call_ollama.sh:14),
so `./scripts/call_ollama.sh` (and its three siblings) can and do exit 4
today for "envelope failed validation" — nothing to do with "nothing ran."

Separately, `evals/judge.sh:48` already `exit 4`s for "no judge tier
available" (comment at judge.sh:16 confirms: "runner treats as skip").

Spec 004 (`factory/specs/004-eval-runner-zero-case-exit.md`) assigns exit 4
to `evals/run_eval.sh`'s own top-level exit status for "zero cases executed,"
without ever mentioning these two pre-existing uses. The scopes don't
mechanically collide today (run_eval.sh's own top-level `$?` vs. a shim
subprocess's `$?` captured inside `run_case()`, vs. judge.sh's exit code
swallowed in a `2>/dev/null | jq` pipe with `|| score=""`), but the numeral
"4" is not a fresh signal in this codebase — it already means "validation
failed" (common.sh) and "no judge tier" (judge.sh). Many downstream specs
(001, 002, 003, 005, 007, 008, 009, 010, 011 — grep `"exit 4"` in
`factory/specs/`) now quote spec 004's "it exits 4" language verbatim in
their own build-order notes.

**Why:** an overloaded exit-code vocabulary across a codebase's shell layer
is a classic source of "which meaning did this 4 come from" bugs, especially
when a spec later asks a builder to write bash-unit cases that invoke both
`run_eval.sh` and (transitively, via shim cases) the call_*.sh scripts as
subprocesses and assert on `$?`.

**How to apply:** whenever a spec proposes a new exit code for a script,
grep the whole repo for existing uses of that numeral in adjacent
scripts/libraries before treating the choice as safe, not just the file
being modified.
