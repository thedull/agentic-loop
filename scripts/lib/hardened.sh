#!/usr/bin/env bash
# hardened.sh — the payload behind `profile: hardened` (spec 005).
#
# Security is one bullet in the standard review. That is a prompt line, and it
# was the entirety of our posture for shipped code. This is the depth the
# `hardened` position routes to — and the reason spec 001's resolver refuses
# `hardened` until this file's marker exists.
#
#   hardened.sh classes                  print the declared class list
#   hardened.sh verdicts <report>        every class has an explicit verdict
#   hardened.sh boundaries <report>      every named boundary has an abuse case
#   hardened.sh supply-chain <diff>      exit 7 if the diff touches dep surface
#
# Exit: 0 ok · 2 the report is incomplete · 7 supply-chain surface touched.

set -uo pipefail
_h_die() { echo "hardened: $1" >&2; exit 2; }

_h_classfile() {
  local root; root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "${HARDENED_CLASSES:-$root/templates/hardened-classes.txt}"
}

hardened_classes() {
  local f line; f="$(_h_classfile)"
  [[ -r "$f" ]] || _h_die "class list not readable at $f"
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] && echo "$line"
  done < "$f"
}

# verdicts REPORT — refuse unless every class carries an explicit verdict.
hardened_verdicts() {
  local report="${1:-}" c missing=0 line
  [[ -n "$report" && -f "$report" ]] || _h_die "usage: hardened.sh verdicts <report>"
  while IFS= read -r c; do
    # The class name is data, not a pattern — escape it before it meets a regex.
    local esc; esc="$(printf '%s' "$c" | sed 's/[][\\.*^$(){}?+|/]/\\\\&/g')"
    line="$(grep -m1 -E "^[[:space:]]*[-*][[:space:]]*${esc}[[:space:]]*:" "$report" 2>/dev/null || true)"
    if [[ -z "$line" ]]; then
      echo "hardened: class '$c' has no verdict — silence is indistinguishable from 'did not look'" >&2
      missing=1; continue
    fi
    # `n/a` is a verdict only when it carries a reason. A bare n/a is silence
    # wearing a verdict, which is the failure mode this whole sweep exists for.
    if printf '%s' "$line" | grep -qiE ':[[:space:]]*(n/?a|not[[:space:]]applicable)[[:space:]]*$'; then
      echo "hardened: class '$c' is marked not-applicable with no reason — state why it does not apply" >&2
      missing=1
    fi
  done < <(hardened_classes)
  [[ $missing -eq 0 ]] || exit 2
  echo "hardened: all classes carry a verdict"
}

# boundaries REPORT — every `boundary:` needs at least one `abuse:` under it.
hardened_boundaries() {
  local report="${1:-}" bad=0
  [[ -n "$report" && -f "$report" ]] || _h_die "usage: hardened.sh boundaries <report>"
  local n; n="$(grep -ciE '^[[:space:]]*[-*][[:space:]]*boundary[[:space:]]*:' "$report" || true)"
  [[ "$n" -gt 0 ]] || _h_die "no trust boundary named — a hardened review sketches the boundaries the change crosses"
  # One awk pass: a boundary is satisfied only if an `abuse:` appears before
  # the next boundary. Done in awk rather than a shell read loop because `read`
  # splits on newlines and a boundary block is inherently multi-line.
  local report_out
  report_out="$(awk '
    function flush() {
      if (cur != "" && !seen) { print "MISSING\t" cur }
    }
    /^[[:space:]]*[-*][[:space:]]*[Bb]oundary[[:space:]]*:/ {
      flush(); cur = $0; seen = 0; next
    }
    cur != "" && /[Aa]buse[[:space:]]*:/ { seen = 1 }
    END { flush() }
  ' "$report")"
  if [[ -n "$report_out" ]]; then
    while IFS=$'\t' read -r _ line; do
      echo "hardened: boundary without an abuse case: $line" >&2
      echo "          name a concrete abuse, not a reminder that boundaries exist" >&2
    done <<< "$report_out"
    bad=1
  fi
  [[ $bad -eq 0 ]] || exit 2
  echo "hardened: every boundary carries an abuse case"
}

# supply-chain DIFF — exit 7 when dependency surface is touched.
hardened_supply_chain() {
  local diff="${1:-}"
  [[ -n "$diff" && -f "$diff" ]] || _h_die "usage: hardened.sh supply-chain <diff>"
  if grep -qE '^(\+\+\+|---|diff --git).*(package(-lock)?\.json|yarn\.lock|pnpm-lock\.yaml|requirements\.txt|poetry\.lock|Pipfile\.lock|go\.(mod|sum)|Cargo\.(toml|lock)|Gemfile(\.lock)?|composer\.(json|lock)|\.nvmrc|Dockerfile|install\.sh|postinstall)' "$diff"; then
    echo "hardened: the diff touches dependency or install surface — report the change, its reachability from this spec's own code paths, and whether a fix or alternative exists" >&2
    exit 7
  fi
  echo "hardened: no dependency surface touched"
}

case "${1:-}" in
  classes)      shift; hardened_classes "$@" ;;
  verdicts)     shift; hardened_verdicts "$@" ;;
  boundaries)   shift; hardened_boundaries "$@" ;;
  supply-chain) shift; hardened_supply_chain "$@" ;;
  *) _h_die "usage: hardened.sh classes | verdicts <report> | boundaries <report> | supply-chain <diff>" ;;
esac
