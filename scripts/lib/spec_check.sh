#!/usr/bin/env bash
# spec_check.sh — check a spec against itself, before the reviewer is spent.
#
#   spec_check.sh <spec file>
#     exit 0  consistent (candidates may still be printed to stderr)
#     exit 2  BLOCKED — the spec contradicts itself on a decidable fact
#
# The design is one routing rule: a gate refuses on decidable facts; a reviewer
# judges. Checks 1 and 2 are set operations over paths and integers, so they
# block. Checks 3 and 4 need reading, so they narrow the candidate set and the
# blind spec-review adjudicates. Putting an LLM inside a gate is the thing this
# repo consistently refuses.

set -uo pipefail
_sc_die() { echo "spec_check: $1" >&2; exit 2; }
FILE="${1:-}"
[[ -n "$FILE" && -f "$FILE" ]] || _sc_die "usage: spec_check.sh <spec file>"

# --- section extraction -------------------------------------------------------
_sec_acceptance() { tr -d '\r' < "$FILE" | awk '/^## Acceptance/{on=1;next} /^## /{on=0} on'; }
_sec_brief()      { tr -d '\r' < "$FILE" | awk '/^## Brief/{on=1;next} /^## /{on=0} on'; }

BLOCK=0
CANDIDATES=0

# --- check 1: an acceptance naming a path absent from input_paths -------------
# Notes, Revision log and Check-command are deliberately NOT read: fixture
# provenance is not scope, and a spec may cite history without widening its
# seams. The reverse direction is deliberately not checked either — see the
# spec's Notes: requiring it would contradict the template, which says
# acceptances are behavioural while input_paths are the seams.
DECLARED="$(_sec_brief | sed -n 's/^- \*\*input_paths\*\*: *//p' | tr ',' '\n' | tr -d '`' | tr -d ' ')"

# Compare paths the way a reader would. Three equivalences, each of which was a
# false block on this checker's first run against the real queue:
#   ./evals/run_eval.sh == evals/run_eval.sh   (leading ./)
#   scripts/lib/        covers scripts/lib/x.sh (a declared directory)
#   obs.sh              == scripts/lib/obs.sh   (same file, shorter reference)
_declared_covers() {
  local p="${1#./}" d
  while IFS= read -r d; do
    d="${d#./}"; [[ -n "$d" ]] || continue
    [[ "$p" == "$d" ]] && return 0
    [[ "$d" == */ && "$p" == "$d"* ]] && return 0
    # A bare filename in an acceptance (`obs.sh`) is a shorter way of naming a
    # declared path. Two DIFFERENT directories sharing a basename are not the
    # same file — this repo has eight `SKILL.md`s.
    [[ "$p" != */* && "${p}" == "${d##*/}" ]] && return 0
  done <<< "$DECLARED"
  return 1
}

while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if ! _declared_covers "$path"; then
    echo "spec_check: acceptance names '$path', which input_paths does not declare" >&2
    BLOCK=1
  fi
done < <(_sec_acceptance | grep -oE '`[A-Za-z0-9_./ -]+\.(sh|jq|md|json|js|txt|py)`' \
         | tr -d '`' | sort -u)

# --- check 2: stale and duplicated acceptance numbers -------------------------
NUMS="$(_sec_acceptance | grep -oE '^[0-9]+\.' | tr -d '.')"
COUNT="$(printf '%s\n' "$NUMS" | grep -c '[0-9]' || true)"
HIGHEST="$(printf '%s\n' "$NUMS" | sort -n | tail -1)"
[[ -n "${HIGHEST:-}" ]] || HIGHEST=0

# 2a — duplicated numbers. Same internal-inconsistency class as a stale
# reference, and the plain stale check misses it entirely: spec 011 shipped
# with two acceptance 7s, introduced by its own gating pass.
while IFS= read -r dup; do
  [[ -n "$dup" ]] || continue
  echo "spec_check: duplicate acceptance number $dup — two acceptances share it" >&2
  BLOCK=1
done < <(printf '%s\n' "$NUMS" | grep '[0-9]' | sort -n | uniq -d)

# 2b — a Notes or Revision-log entry citing an acceptance that does not exist.
while IFS= read -r n; do
  [[ -n "$n" ]] || continue
  if [[ "$n" -gt "$HIGHEST" ]]; then
    echo "spec_check: Notes cite acceptance $n, but the highest is $HIGHEST" >&2
    BLOCK=1
  fi
done < <(awk '/^## (Notes|Revision)/{on=1} on' "$FILE" \
         | grep -v '"' \
         | sed -E 's/spec [0-9]+[^.]*acceptance [0-9]+//gi; s/acceptance [0-9]+ of [^.]*//gi' \
         | grep -oiE 'acceptance [0-9]+' | grep -oE '[0-9]+' | sort -un)

# --- check 3: vocabulary drift (CANDIDATE, never blocking) --------------------
# Known miss, pinned as a fixture: when the drifted term reappears anywhere in
# the acceptances — including unrelated prose — a presence check finds it and
# stays silent. That is how spec 011's real drift escaped. Deciding it properly
# means knowing output_spec names something AS A REPORTED FIELD and no
# acceptance does, which is reading, not matching.
ACC_TEXT="$(_sec_acceptance | tr '[:upper:]' '[:lower:]')"
while IFS= read -r term; do
  [[ ${#term} -ge 6 ]] || continue
  case "$term" in a|an|the|and|that|this|with|from|when|then|given|shall|report|naming) continue ;; esac
  if ! printf '%s' "$ACC_TEXT" | grep -qF -- "$term"; then
    echo "spec_check: candidate — output_spec says '$term', which appears in no acceptance" >&2
    CANDIDATES=$((CANDIDATES+1))
  fi
done < <(_sec_brief | sed -n 's/^- \*\*output_spec\*\*: *//p' \
         | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | sort -u)

# --- check 4: boundary clash (CANDIDATE, never blocking) ----------------------
# Listed even when the acceptance AGREES with the boundary: narrowing what a
# human reads is the goal, not being right.
while IFS= read -r bnd; do
  [[ -n "$bnd" ]] || continue
  hits=0
  for w in $(printf '%s' "$bnd" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '\n' | sort -u); do
    [[ ${#w} -ge 6 ]] || continue
    printf '%s' "$ACC_TEXT" | grep -qF -- "$w" && hits=$((hits+1))
  done
  if [[ $hits -ge 1 ]]; then
    echo "spec_check: candidate — boundary '$bnd' shares terms with an acceptance" >&2
    CANDIDATES=$((CANDIDATES+1))
  fi
done < <(_sec_brief | sed -n 's/^ *- Does NOT */Does NOT /p')

[[ $CANDIDATES -gt 0 ]] && \
  echo "spec_check: $CANDIDATES candidate(s) for the reviewer — these narrow the reading, they do not decide it" >&2

if [[ $BLOCK -eq 1 ]]; then
  echo "spec_check: BLOCKED — the spec contradicts itself on a decidable fact; fix before specd" >&2
  exit 2
fi
echo "spec_check: consistent ($CANDIDATES candidate(s))"
