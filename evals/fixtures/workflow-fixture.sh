# workflow-fixture.sh — helpers for evals/cases/workflow/*.
# Sourced by a bash-unit case's $cmd; cwd is the eval's mktemp sandbox.
#
# workflow.sh's unit is the region-marked file, and cases need exact control
# over individual lines (marker syntax, trailing whitespace, blank lines,
# decoy text) — a single content string like scaffold_put's isn't enough.

# wf_file PATH LINE... — write PATH as one line per remaining arg, in order.
# Each arg becomes exactly one line (newline-joined); an empty arg "" is a
# blank line. Use this for both fixtures and hand-built "expected" files so
# byte-exact comparisons (cmp -s) are comparing like-built content.
wf_file() {
  local path="$1"; shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$@" > "$path"
}
