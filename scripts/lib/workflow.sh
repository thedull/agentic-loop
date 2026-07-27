#!/usr/bin/env bash
# Region-owned files — sub-file ownership between the plugin and a project.
#
# Why this exists (field evidence, 2026-07-27): a project's production line is
# never quite the stock one, but `scaffold.sh` ownership is all-or-nothing per
# FILE. A project that edits its workflow becomes `modified` -> the user says
# "keep mine" -> `kept` -> frozen forever, receiving no upstream improvement.
# xeneon-edge-mac hit exactly that: it forked factory.js, and the fork silently
# DROPPED the review stage's "record needs_escalation instead" clause and
# pinned a skill path at plugin 0.6.0. Forking loses policy by omission.
#
# So ownership moves inside the file. A region is a marked span:
#
#   // @agentic-loop:begin region=review-prompt owner=plugin after=build-prompt
#   ...
#   // @agentic-loop:end region=review-prompt
#
# LINE comments only — block comments get reflowed by formatters, and a
# reflowed marker is an unparseable file. `region=` is the ONLY identity the
# merge trusts: never line numbers, never surrounding text. Content OUTSIDE any
# marker is PROJECT-owned by default, so the file is the project's and only
# what the plugin explicitly wraps is refreshable.
#
# Refusal beats guessing. Unbalanced/nested markers, or an owner that disagrees
# between project and template, abort with a nonzero exit and write NOTHING —
# unlike scaffold_status, which degrades gracefully. Degrading gracefully on a
# whole hand-edited file is safe; guessing your way through a corrupt region
# seam is how a policy region gets silently clobbered.
#
# CLI:
#   workflow.sh regions FILE [PREFIX]            name<TAB>owner<TAB>after
#   workflow.sh diff PROJECT TEMPLATE [PREFIX]   JSON verdict, writes nothing
#   workflow.sh merge PROJECT TEMPLATE [PREFIX]  refresh plugin regions in place
#   workflow.sh sums TEMPLATE [PREFIX]           {region: checksum} for stamping
#
# PREFIX is the line-comment marker, default `//`. Pass `#` for shell or
# `<!--` for Markdown — the only language-specific knob, so a non-JS line kind
# needs no redesign.

set -uo pipefail

WORKFLOW_MARKER="${WORKFLOW_MARKER:-@agentic-loop}"

_wf_sum_string() { # stdin -> sha256, matching scaffold_checksum's algorithm
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum 2>/dev/null | awk '{print $1}'
  fi
  return 0
}

# _wf_scan FILE PREFIX — validate and emit one TSV row per region:
#   name<TAB>owner<TAB>after<TAB>startLine<TAB>endLine
# Exit 3 with a CORRUPT: message on any structural problem.
_wf_scan() {
  awk -v marker="$WORKFLOW_MARKER" -v pfx="$1" '
    function attr(line, key,   m) {
      m = line
      if (match(m, key "=[A-Za-z0-9_.-]+")) {
        return substr(m, RSTART + length(key) + 1, RLENGTH - length(key) - 1)
      }
      return ""
    }
    # A marker line is: <optional space> <prefix> <space> @marker:begin|end ...
    index($0, marker ":begin") > 0 && index($0, pfx) > 0 {
      if (open != "") {
        printf "CORRUPT: nested begin (region=%s) at line %d while region=%s is open\n", \
          attr($0, "region"), NR, open > "/dev/stderr"; exit 3
      }
      open = attr($0, "region"); owner = attr($0, "owner"); after = attr($0, "after")
      if (open == "") { printf "CORRUPT: begin without region= at line %d\n", NR > "/dev/stderr"; exit 3 }
      if (owner != "plugin" && owner != "project") {
        printf "CORRUPT: region=%s has owner=%s (must be plugin|project) at line %d\n", \
          open, owner, NR > "/dev/stderr"; exit 3
      }
      if (open in seen) { printf "CORRUPT: duplicate region=%s at line %d\n", open, NR > "/dev/stderr"; exit 3 }
      seen[open] = 1; start = NR; next
    }
    index($0, marker ":end") > 0 && index($0, pfx) > 0 {
      name = attr($0, "region")
      if (open == "") { printf "CORRUPT: end (region=%s) with no open region at line %d\n", name, NR > "/dev/stderr"; exit 3 }
      if (name != "" && name != open) {
        printf "CORRUPT: end region=%s closes region=%s at line %d\n", name, open, NR > "/dev/stderr"; exit 3
      }
      # "-" for an absent anchor, never "": tab is IFS-whitespace, so bash
      # `read` collapses an empty field and silently shifts every column after
      # it (this cost a debugging round on 2026-07-27).
      printf "%s\t%s\t%s\t%d\t%d\n", open, owner, (after == "" ? "-" : after), start, NR
      open = ""; next
    }
    END {
      if (open != "") { printf "CORRUPT: region=%s never closed (EOF)\n", open > "/dev/stderr"; exit 3 }
    }
  ' "$2"
}

# workflow_regions FILE [PREFIX] — name<TAB>owner<TAB>after
workflow_regions() {
  local file="$1" pfx="${2:-//}" name owner after _s _e
  _wf_scan "$pfx" "$file" | while IFS=$'\t' read -r name owner after _s _e; do
    [[ "$after" == "-" ]] && after=""
    printf '%s\t%s\t%s\n' "$name" "$owner" "$after"
  done
}

# _wf_body FILE START END — the region's full text INCLUDING marker lines.
_wf_body() { sed -n "${2},${3}p" "$1"; }

# _wf_find NAME SCANOUT — echo "owner<TAB>after<TAB>start<TAB>end" or empty.
_wf_find() {
  printf '%s\n' "$2" | awk -F'\t' -v n="$1" '$1==n {printf "%s\t%s\t%s\t%s\n",$2,$3,$4,$5; exit}'
}

# workflow_sums TEMPLATE [PREFIX] — {"<region>": "<sha256 of its body>"}.
# Stamped from the TEMPLATE, never the project's copy — same invariant as
# scaffold_write_stamp: record what upstream shipped, so a later hand-edit
# inside a plugin region reads as an edit instead of as "already current".
workflow_sums() {
  local file="$1" pfx="${2:-//}" scan out='{}' name owner after s e sum
  scan="$(_wf_scan "$pfx" "$file")" || return 3
  while IFS=$'\t' read -r name owner after s e; do
    [[ -n "$name" && "$owner" == "plugin" ]] || continue
    sum="$(_wf_body "$file" "$s" "$e" | _wf_sum_string)"
    out="$(printf '%s' "$out" | jq -c --arg k "$name" --arg v "$sum" '.[$k]=$v')" || return 1
  done <<< "$scan"
  printf '%s' "$out"
}

# _wf_verdict PROJECT TEMPLATE PREFIX STAMP_JSON — the shared analysis behind
# both `diff` and `merge`. Emits JSON; exit 3 if either file is corrupt.
_wf_verdict() {
  local proj="$1" tpl="$2" pfx="$3" stamp="${4:-\{\}}"
  local pscan tscan name owner after s e town tafter ts te
  local refreshed='[]' new='[]' orphaned='[]' unchanged='[]' conflict='[]'
  pscan="$(_wf_scan "$pfx" "$proj")" || return 3
  tscan="$(_wf_scan "$pfx" "$tpl")"  || return 3

  local psum tsum stamped hit
  while IFS=$'\t' read -r name owner after s e; do
    [[ -n "$name" ]] || continue
    [[ "$owner" == "plugin" ]] || continue          # project regions: never touched
    hit="$(_wf_find "$name" "$tscan")"
    if [[ -z "$hit" ]]; then
      orphaned="$(jq -c --arg n "$name" '. + [$n]' <<<"$orphaned")"; continue
    fi
    IFS=$'\t' read -r town tafter ts te <<< "$hit"
    if [[ "$town" != "plugin" ]]; then
      conflict="$(jq -c --arg n "$name" --arg r "owner mismatch: project=plugin template=$town" \
        '. + [{region:$n, reason:$r}]' <<<"$conflict")"; continue
    fi
    psum="$(_wf_body "$proj" "$s" "$e" | _wf_sum_string)"
    tsum="$(_wf_body "$tpl" "$ts" "$te" | _wf_sum_string)"
    if [[ "$psum" == "$tsum" ]]; then
      unchanged="$(jq -c --arg n "$name" '. + [$n]' <<<"$unchanged")"; continue
    fi
    # Differs from upstream. Was it upstream's previous body, or a hand edit?
    stamped="$(jq -r --arg n "$name" '.[$n] // empty' <<<"$stamp" 2>/dev/null)"
    if [[ -n "$stamped" && "$psum" != "$stamped" ]]; then
      conflict="$(jq -c --arg n "$name" \
        --arg r "edited inside a plugin-owned region — refusing to overwrite" \
        '. + [{region:$n, reason:$r}]' <<<"$conflict")"
    else
      refreshed="$(jq -c --arg n "$name" '. + [$n]' <<<"$refreshed")"
    fi
  done <<< "$pscan"

  while IFS=$'\t' read -r name owner after ts te; do
    [[ -n "$name" && "$owner" == "plugin" ]] || continue
    [[ -z "$(_wf_find "$name" "$pscan")" ]] || continue
    [[ "$after" == "-" ]] && after=""
    new="$(jq -c --arg n "$name" --arg a "$after" '. + [{region:$n, after:$a}]' <<<"$new")"
  done <<< "$tscan"

  jq -cn --argjson r "$refreshed" --argjson n "$new" --argjson o "$orphaned" \
         --argjson u "$unchanged" --argjson c "$conflict" \
    '{refreshed:$r, new:$n, orphaned:$o, unchanged:$u, conflict:$c}'
}

# workflow_diff PROJECT TEMPLATE [PREFIX] [STAMP_JSON] — verdict, no writes.
workflow_diff() { _wf_verdict "$1" "$2" "${3:-//}" "${4:-\{\}}"; }

# workflow_merge PROJECT TEMPLATE [PREFIX] [STAMP_JSON] — refresh plugin
# regions in place. Project regions and all unmarked text are byte-for-byte
# preserved. Conflicted and orphaned regions are left exactly as they are.
# Writes only if the bytes actually change, so a re-run is a silent no-op.
workflow_merge() {
  local proj="$1" tpl="$2" pfx="${3:-//}" stamp="${4:-\{\}}"
  local verdict pscan tscan tmp name owner after s e hit town tafter ts te
  verdict="$(_wf_verdict "$proj" "$tpl" "$pfx" "$stamp")" || return 3
  pscan="$(_wf_scan "$pfx" "$proj")" || return 3
  tscan="$(_wf_scan "$pfx" "$tpl")"  || return 3
  tmp="$(mktemp "${proj}.XXXXXX")" || return 1

  # Regions we are cleared to replace (conflicts/orphans deliberately absent).
  local refresh_list; refresh_list="$(jq -r '.refreshed[]' <<<"$verdict")"

  local line_no=0 skip_to=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))
    if [[ $skip_to -gt 0 ]]; then
      [[ $line_no -ge $skip_to ]] && skip_to=0
      continue
    fi
    hit="$(printf '%s\n' "$pscan" | awk -F'\t' -v n="$line_no" '$4==n {print; exit}')"
    if [[ -n "$hit" ]]; then
      IFS=$'\t' read -r name owner after s e <<< "$hit"
      if [[ "$owner" == "plugin" ]] && grep -qxF "$name" <<<"$refresh_list"; then
        IFS=$'\t' read -r town tafter ts te <<< "$(_wf_find "$name" "$tscan")"
        _wf_body "$tpl" "$ts" "$te" >> "$tmp"     # upstream's current body
        skip_to=$e                                 # drop the project's old one
        continue
      fi
    fi
    printf '%s\n' "$line" >> "$tmp"
  done < "$proj"

  # Regions upstream added that this file predates: splice after their anchor
  # when we can find it, else append.
  local newname newafter anchor
  while IFS=$'\t' read -r newname newafter; do
    [[ -n "$newname" ]] || continue
    IFS=$'\t' read -r town tafter ts te <<< "$(_wf_find "$newname" "$tscan")"
    anchor="$(_wf_scan "$pfx" "$tmp" | awk -F'\t' -v a="$newafter" '$1==a {print $5; exit}')"
    if [[ -n "$anchor" && -n "$newafter" ]]; then
      { sed -n "1,${anchor}p" "$tmp"; echo; _wf_body "$tpl" "$ts" "$te"
        sed -n "$((anchor + 1)),\$p" "$tmp"; } > "${tmp}.ins" && mv "${tmp}.ins" "$tmp"
    else
      { echo; _wf_body "$tpl" "$ts" "$te"; } >> "$tmp"
    fi
  done < <(jq -r '.new[] | [.region, .after] | @tsv' <<<"$verdict")

  if cmp -s "$tmp" "$proj"; then rm -f "$tmp"; else mv "$tmp" "$proj"; fi
  printf '%s' "$verdict"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    regions) workflow_regions "$@" ;;
    sums)    workflow_sums "$@" ;;
    diff)    workflow_diff "$@" ;;
    merge)   workflow_merge "$@" ;;
    *) echo "usage: workflow.sh regions|sums|diff|merge ..." >&2; exit 2 ;;
  esac
fi
