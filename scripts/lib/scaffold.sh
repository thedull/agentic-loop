#!/usr/bin/env bash
# scaffold.sh — the plugin-owned file manifest, version stamp, and drift check.
#
# Why this exists (field evidence, 2026-07-27): /agentic-loop:init copies
# plugin-owned files into a project, and those copies then rot silently. Two
# projects scaffolded months apart were both still carrying a tracker.sh from
# before `depends_on` existed and had never heard of bench.sh — with nothing
# anywhere to say so. Shipping a fix to the plugin does not ship it to the
# projects; only a mechanical update path does.
#
# Ownership contract:
#   PLUGIN-OWNED (the manifest below) — /agentic-loop:update replaces these.
#     Projects are not expected to patch them. If one is patched anyway, the
#     stamped checksum no longer matches and update ASKS instead of clobbering.
#   USER-OWNED (everything else: CLAUDE.md, LOOP_POLICY.md, LEARNINGS.md,
#     .agentic/, factory/specs/) — update never writes these. LOOP_POLICY.md
#     especially: init deletes its factory section for interviewed-software
#     projects, so divergence there is correct, not drift.
#
# `scripts/` is a SHARED directory, not a plugin-owned one — real projects keep
# their own scripts beside ours (scripts/build-app.sh, scripts/assets/*.mjs
# were both observed in the field). That is precisely why this is an
# enumerated manifest and never an `rm -rf scripts/`.
#
# The stamp is COMMITTED (scripts/.agentic-scaffold.json) so it travels with
# the files it describes: a fresh clone gets a correct drift verdict instead
# of "unknown". Media/other projects scaffold no scripts and get no stamp.
#
# CLI:
#   scaffold.sh manifest [type]        dest<TAB>source<TAB>tier, one per line
#   scaffold.sh status <plugin-root>   dest<TAB>state per file (see below)
#   scaffold.sh trace <dest> <src> <plugin-root>   commit an unverified file
#                                      matches, proving it a clean old copy
#   scaffold.sh stamp <plugin-root> <type> [source-label]   write the stamp
#   scaffold.sh version                stamped plugin version ("" if unstamped)
#   scaffold.sh plugin-root            best-effort discovery of an install
#
# States emitted by `status`:
#   ok          project copy is byte-identical to the plugin's
#   stale       still exactly what upstream gave us; upstream has moved on —
#               nobody edited it, so it is safe to replace
#   modified    differs from what upstream gave us AND from upstream now — a
#               real local edit; a human must decide
#   unverified  differs from the plugin and there is no stamp entry to compare
#               against (a project scaffolded before stamping existed). Not the
#               same claim as `modified`: we do not know, so we do not assert
#   kept        on the stamp's `keep` list — the user already chose to hold
#               their version; reported, never acted on
#   missing     the plugin ships it, the project does not have it yet
#
# Region-managed files (see `_scaffold_is_region_managed`) get two extra states
# instead of the whole-file verdicts above. Their ownership is per-REGION: the
# project owns the file, the plugin owns marked spans inside it. Whole-file
# ownership cannot express that, and forcing it to made projects choose between
# customizing and ever receiving an update again.
#   regions-updatable  plugin regions moved; nothing conflicts — safe auto-merge
#   regions-conflict   corrupt markers, an owner disagreement, or a hand-edit
#                      inside a plugin region — a human must look
#
# Never fatal: an unreadable stamp or an absent plugin degrades to "modified"/
# "unknown" rather than failing the caller.

# Deliberately no `set -e`: this file is sourced by callers (doctor.sh) that
# want to survive individual failures. The CLI block below sets its own flags.

SCAFFOLD_STAMP_PATH="${SCAFFOLD_STAMP_PATH:-scripts/.agentic-scaffold.json}"

# Files whose ownership is per-region rather than whole-file. Everything here
# must carry @agentic-loop markers in the plugin's copy; workflow.sh does the
# merge. Keep the list tiny — region ownership is for files a project is
# EXPECTED to edit (its production line), not for library scripts.
_scaffold_region_managed() {
  cat <<'REGIONS'
.claude/workflows/factory.js	//
REGIONS
}

# _scaffold_is_region_managed DEST — print its comment prefix, or nothing.
_scaffold_is_region_managed() {
  _scaffold_region_managed | awk -F'\t' -v d="$1" '$1==d {print $2; exit}'
}

# _scaffold_workflow_lib — path to workflow.sh next to this file ("" if absent).
_scaffold_workflow_lib() {
  local d; d="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$d/workflow.sh" ]] && printf '%s' "$d/workflow.sh"
  return 0
}

# _scaffold_regions_adopted DEST PFX WF — true when DEST actually carries
# markers. A project scaffolded before regions existed has NONE, and merging
# into it would splice every plugin region on top of the equivalent inline
# code — producing a file with two copies of each stage (caught in a dry run
# against a real project, 2026-07-27, before any project was touched). Such a
# file is not region-managed yet: it falls back to the whole-file lattice,
# where it reads `stale` and is simply replaced, arriving WITH markers.
_scaffold_regions_adopted() {
  local n
  n="$(bash "$3" regions "$1" "$2" 2>/dev/null | grep -c . || true)"
  [[ "${n:-0}" -gt 0 ]]
}

# --- manifest -----------------------------------------------------------------
# dest<TAB>source<TAB>tier. dest is relative to the PROJECT, source to the
# PLUGIN ROOT; they differ wherever init renames on copy. Keep in sync with
# skills/init/SKILL.md step 5 — that copy list and this manifest are the same
# fact stated twice, and the evals check nothing drifts between them.
_scaffold_manifest_all() {
  cat <<'MANIFEST'
scripts/call_fable.sh	scripts/call_fable.sh	core
scripts/call_ollama.sh	scripts/call_ollama.sh	core
scripts/call_openrouter.sh	scripts/call_openrouter.sh	core
scripts/call_sol.sh	scripts/call_sol.sh	core
scripts/doctor.sh	scripts/doctor.sh	core
scripts/observe.sh	scripts/observe.sh	core
scripts/observe_render.sh	scripts/observe_render.sh	core
scripts/run_headless.sh	scripts/run_headless.sh	core
scripts/statusline-usage.sh	templates/statusline-usage.sh	core
scripts/lib/bench.sh	scripts/lib/bench.sh	core
scripts/lib/common.sh	scripts/lib/common.sh	core
scripts/lib/obs.sh	scripts/lib/obs.sh	core
scripts/lib/obs_summary.jq	scripts/lib/obs_summary.jq	core
scripts/lib/scaffold.sh	scripts/lib/scaffold.sh	core
scripts/lib/tracker.sh	scripts/lib/tracker.sh	core
scripts/lib/usage_gate.sh	scripts/lib/usage_gate.sh	core
scripts/lib/validate_envelope.jq	scripts/lib/validate_envelope.jq	core
factory/spec-template.md	templates/factory-spec.md	factory
.claude/workflows/factory.js	templates/workflows/factory.js	factory
MANIFEST
}

# Which tiers a project type receives (mirrors init step 2's type matrix).
_scaffold_tiers() {
  case "${1:-software-unattended}" in
    software-unattended)  printf 'core factory' ;;
    software-interviewed) printf 'core' ;;
    *)                    printf '' ;;   # media / other scaffold no scripts
  esac
}

# scaffold_manifest [TYPE] — manifest rows applicable to TYPE (default:
# the stamped type, else software-unattended).
scaffold_manifest() {
  local type="${1:-}" tiers row tier
  [[ -z "$type" ]] && type="$(scaffold_field project_type)"
  [[ -z "$type" ]] && type="software-unattended"
  tiers="$(_scaffold_tiers "$type")"
  [[ -z "$tiers" ]] && return 0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    tier="${row##*$'\t'}"
    case " $tiers " in *" $tier "*) printf '%s\n' "$row" ;; esac
  done < <(_scaffold_manifest_all)
  return 0
}

# --- checksums ----------------------------------------------------------------
# Portable sha256: macOS ships shasum, most Linuxes sha256sum. Missing file or
# no tool prints nothing — callers treat empty as "cannot verify".
scaffold_checksum() {
  [[ -f "$1" ]] || return 0
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  fi
  return 0
}

# --- stamp --------------------------------------------------------------------
# scaffold_field KEY — a top-level stamp field ("" when unstamped).
scaffold_field() {
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] || return 0
  jq -r --arg k "$1" '.[$k] // empty' "$SCAFFOLD_STAMP_PATH" 2>/dev/null
  return 0
}

# scaffold_stamped_sum DEST — the checksum recorded for DEST at install time.
scaffold_stamped_sum() {
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] || return 0
  jq -r --arg f "$1" '.checksums[$f] // empty' "$SCAFFOLD_STAMP_PATH" 2>/dev/null
  return 0
}

# scaffold_region_sums DEST — {region: checksum} recorded for a region-managed
# file ("{}" when unstamped). This is what lets a hand-edit INSIDE a plugin
# region be told apart from that region simply being an older upstream body.
scaffold_region_sums() {
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] || { printf '{}'; return 0; }
  jq -c --arg f "$1" '(.region_checksums[$f] // {})' \
    "$SCAFFOLD_STAMP_PATH" 2>/dev/null || printf '{}'
  return 0
}

# scaffold_plugin_version ROOT — the plugin's own declared version.
scaffold_plugin_version() {
  jq -r '.version // empty' "$1/.claude-plugin/plugin.json" 2>/dev/null
  return 0
}

# scaffold_plugin_root — best-effort discovery, for tools that were not handed
# a root (doctor.sh). AGENTIC_PLUGIN_ROOT wins; otherwise the highest-numbered
# installed cache entry. Prints nothing when it cannot tell — an honest
# "unknown" beats guessing at a wrong root.
scaffold_plugin_root() {
  if [[ -n "${AGENTIC_PLUGIN_ROOT:-}" && -f "$AGENTIC_PLUGIN_ROOT/.claude-plugin/plugin.json" ]]; then
    printf '%s' "$AGENTIC_PLUGIN_ROOT"; return 0
  fi
  local cache d best=""
  cache="${CLAUDE_PLUGIN_CACHE:-$HOME/.claude/plugins/cache/agentic-loop/agentic-loop}"
  [[ -d "$cache" ]] || return 0
  for d in "$cache"/*/; do
    [[ -f "$d/.claude-plugin/plugin.json" ]] || continue
    if [[ -z "$best" ]]; then best="$d"; continue
    fi
    # sort -V keeps 0.10.0 above 0.9.0; plain string compare would not.
    [[ "$(printf '%s\n%s\n' "$(basename "$best")" "$(basename "$d")" \
          | sort -V | tail -1)" == "$(basename "$d")" ]] && best="$d"
  done
  [[ -n "$best" ]] && printf '%s' "${best%/}"
  return 0
}

# scaffold_write_stamp ROOT TYPE [SOURCE_LABEL] — record what UPSTREAM last
# gave us: each checksum is of the PLUGIN's source file, not the project's copy.
#
# That distinction is the whole correctness of this module, and it is not
# obvious. Stamping the project's copy instead looks equivalent — it is
# identical for every file we actually installed — but it silently breaks the
# one case that matters: a file the user chose to KEEP against upstream would
# be stamped at its edited contents, so the next run would see
# current == stamped, call it `stale`, and revert the user's edit. Stamping
# upstream's content instead makes that file read `modified` forever, which is
# exactly what it is.
#
# An existing `keep` list survives a re-stamp — it is the user's decision, not
# derived state.
scaffold_write_stamp() {
  local root="$1" type="$2" label="${3:-$1}" dest src sums="{}" sum keep='[]'
  local version; version="$(scaffold_plugin_version "$root")"
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] && keep="$(jq -c '.keep // []' \
    "$SCAFFOLD_STAMP_PATH" 2>/dev/null || echo '[]')"
  local rsums='{}' pfx wf one
  wf="$(_scaffold_workflow_lib)"
  while IFS=$'\t' read -r dest src _tier; do
    [[ -n "$dest" ]] || continue
    sum="$(scaffold_checksum "$root/$src")"
    [[ -n "$sum" ]] || continue
    sums="$(printf '%s' "$sums" | jq -c --arg f "$dest" --arg s "$sum" \
            '.[$f] = $s' 2>/dev/null)" || return 1
    # Region-managed files also get per-region sums, taken from UPSTREAM's
    # body for the same reason the file-level sum is (see the note above).
    pfx="$(_scaffold_is_region_managed "$dest")"
    if [[ -n "$pfx" && -n "$wf" ]]; then
      one="$(bash "$wf" sums "$root/$src" "$pfx" 2>/dev/null)"
      [[ -n "$one" ]] && rsums="$(printf '%s' "$rsums" | jq -c \
        --arg f "$dest" --argjson r "$one" '.[$f] = $r' 2>/dev/null)"
    fi
  done < <(scaffold_manifest "$type")
  mkdir -p "$(dirname "$SCAFFOLD_STAMP_PATH")" 2>/dev/null || true
  jq -n --arg v "$version" --arg t "$type" --arg src "$label" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson sums "$sums" \
        --argjson keep "$keep" --argjson rsums "$rsums" '
    {plugin_version: $v, project_type: $t, source: $src,
     updated_at: $at, keep: $keep, checksums: $sums,
     region_checksums: $rsums}' \
    > "$SCAFFOLD_STAMP_PATH" || return 1
  return 0
}

# scaffold_keep DEST... — record that the user deliberately kept their own
# version of these files. Without this, update must re-ask about the same edit
# on every run, which contradicts its "re-running is a clean no-op" rule.
scaffold_keep() {
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] || return 0
  local add tmp
  # Build the array explicitly rather than with jq --args: that flag also
  # swallows the filename as a positional, which silently wrote an EMPTY
  # stamp (caught in an end-to-end replay, 2026-07-27).
  # Trim and drop empties: this is driven by an agent following the update
  # skill, and a path that arrives padded (" scripts/x.sh") would match no
  # manifest entry and make the whole call a SILENT no-op — i.e. the user's
  # kept edit would be reverted on the next run. Fail loudly instead.
  add="$(printf '%s\n' "$@" | jq -R . | jq -cs \
        'map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0))')" 2>/dev/null \
    || return 1
  [[ "$add" == "[]" ]] && { echo "scaffold: keep got no usable paths" >&2; return 1; }
  tmp="$(mktemp "${SCAFFOLD_STAMP_PATH}.XXXXXX")" || return 1
  if jq --argjson add "$add" \
       '.keep = ((.keep // []) + $add | unique)' \
       "$SCAFFOLD_STAMP_PATH" > "$tmp" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv "$tmp" "$SCAFFOLD_STAMP_PATH"
  else
    rm -f "$tmp"; return 1
  fi
  return 0
}

# _scaffold_is_kept DEST — is this path on the stamp's keep list?
_scaffold_is_kept() {
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] || return 1
  jq -e --arg f "$1" '((.keep // []) | index($f)) != null' \
    "$SCAFFOLD_STAMP_PATH" >/dev/null 2>&1
}

# --- drift --------------------------------------------------------------------
# scaffold_status ROOT [TYPE] — dest<TAB>state for every applicable file.
scaffold_status() {
  local root="$1" type="${2:-}" dest src _tier cur stamped up
  while IFS=$'\t' read -r dest src _tier; do
    [[ -n "$dest" ]] || continue
    if [[ ! -f "$root/$src" ]]; then
      continue                       # plugin does not ship it (older plugin)
    fi
    if [[ ! -f "$dest" ]]; then
      printf '%s\tmissing\n' "$dest"; continue
    fi
    cur="$(scaffold_checksum "$dest")"
    up="$(scaffold_checksum "$root/$src")"
    if [[ -n "$cur" && "$cur" == "$up" ]]; then
      printf '%s\tok\n' "$dest"; continue
    fi
    # Region-managed: differing bytes are EXPECTED (the project owns most of
    # the file), so ask workflow.sh which regions actually moved.
    local pfx wf verdict nconf nref nnew orph
    pfx="$(_scaffold_is_region_managed "$dest")"
    wf="$(_scaffold_workflow_lib)"
    if [[ -n "$pfx" && -n "$wf" ]] && _scaffold_regions_adopted "$dest" "$pfx" "$wf"; then
      # shellcheck disable=SC1090
      verdict="$(bash "$wf" diff "$dest" "$root/$src" "$pfx" \
                 "$(scaffold_region_sums "$dest")" 2>/dev/null)"
      if [[ -z "$verdict" ]]; then
        printf '%s\tregions-conflict\tunparseable markers\n' "$dest"; continue
      fi
      nconf="$(jq -r '.conflict | length' <<<"$verdict" 2>/dev/null || echo 0)"
      nref="$(jq -r '.refreshed | length' <<<"$verdict" 2>/dev/null || echo 0)"
      nnew="$(jq -r '.new | length' <<<"$verdict" 2>/dev/null || echo 0)"
      orph="$(jq -r '.orphaned | join(",")' <<<"$verdict" 2>/dev/null)"
      if [[ "$nconf" != "0" ]]; then
        printf '%s\tregions-conflict\t%s\n' "$dest" \
          "$(jq -r '[.conflict[].region] | join(",")' <<<"$verdict")"
      elif [[ "$nref" != "0" || "$nnew" != "0" ]]; then
        printf '%s\tregions-updatable%s\n' "$dest" "${orph:+	orphaned:$orph}"
      else
        printf '%s\tok%s\n' "$dest" "${orph:+	orphaned:$orph}"
      fi
      continue
    fi
    if _scaffold_is_kept "$dest"; then
      printf '%s\tkept\n' "$dest"       # the user already decided; do not re-ask
      continue
    fi
    stamped="$(scaffold_stamped_sum "$dest")"
    if [[ -z "$stamped" ]]; then
      printf '%s\tunverified\n' "$dest" # no stamp entry — cannot tell, do not guess
    elif [[ "$cur" == "$stamped" ]]; then
      printf '%s\tstale\n' "$dest"      # still exactly what upstream gave us
    else
      printf '%s\tmodified\n' "$dest"   # differs from upstream-then AND now
    fi
  done < <(scaffold_manifest "$type")
  return 0
}

# scaffold_integrity — dest<TAB>modified|missing for stamped files that no
# longer match their stamp. Needs no plugin root, so doctor.sh can answer
# "has anything here been hand-edited?" even when no install is discoverable.
# Files on the keep list are skipped: the user already decided about those,
# and reporting them as `modified` here while `status` calls them `kept` is
# the same fact told two contradictory ways.
scaffold_integrity() {
  local dest stamped cur
  [[ -f "$SCAFFOLD_STAMP_PATH" ]] || return 0
  while IFS= read -r dest; do
    [[ -n "$dest" ]] || continue
    _scaffold_is_kept "$dest" && continue
    stamped="$(scaffold_stamped_sum "$dest")"
    [[ -n "$stamped" ]] || continue
    if [[ ! -f "$dest" ]]; then printf '%s\tmissing\n' "$dest"; continue; fi
    cur="$(scaffold_checksum "$dest")"
    [[ -n "$cur" && "$cur" != "$stamped" ]] && printf '%s\tmodified\n' "$dest"
  done < <(jq -r '.checksums // {} | keys[]' "$SCAFFOLD_STAMP_PATH" 2>/dev/null)
  return 0
}

# scaffold_trace DEST SRC ROOT — resolve an `unverified` file with certainty.
# When ROOT is a git checkout of the plugin, a project's copy that matches the
# source file at ANY past commit is a clean older copy, not a local edit —
# which turns "cannot tell" into "safe to replace". Prints the short commit
# that matched (empty if none, or if ROOT has no usable history). Bounded to
# the most recent 50 revisions of that path: these files have few commits, and
# an unbounded walk on a large history is not worth the certainty.
scaffold_trace() {
  local dest="$1" src="$2" root="$3" cur c sum
  cur="$(scaffold_checksum "$dest")"
  [[ -n "$cur" ]] || return 0
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0
  while IFS= read -r c; do
    [[ -n "$c" ]] || continue
    sum="$(git -C "$root" show "$c:$src" 2>/dev/null | { \
             if command -v shasum >/dev/null 2>&1; then shasum -a 256; \
             else sha256sum; fi; } 2>/dev/null | awk '{print $1}')"
    if [[ -n "$sum" && "$sum" == "$cur" ]]; then
      printf '%s' "$(git -C "$root" rev-parse --short "$c" 2>/dev/null)"
      return 0
    fi
  done < <(git -C "$root" rev-list --max-count=50 HEAD -- "$src" 2>/dev/null)
  return 0
}

# scaffold_summary ROOT [TYPE] — one JSON object of per-state counts.
scaffold_summary() {
  scaffold_status "$@" | awk -F'\t' '
    {c[$2]++}
    END {printf "{\"ok\":%d,\"stale\":%d,\"modified\":%d,\"unverified\":%d,\"kept\":%d,\"missing\":%d,\"regions-updatable\":%d,\"regions-conflict\":%d}\n",
                c["ok"], c["stale"], c["modified"], c["unverified"], c["kept"], c["missing"],
                c["regions-updatable"], c["regions-conflict"]}'
  return 0
}

# scaffold_merge_regions ROOT [TYPE] — refresh plugin-owned regions in every
# region-managed file. dest<TAB>json-verdict per file. Files whose markers are
# corrupt, or that hold a hand-edit inside a plugin region, are reported and
# left untouched — this never overwrites without the merge engine's consent.
scaffold_merge_regions() {
  local root="$1" type="${2:-}" dest src _tier pfx wf verdict
  wf="$(_scaffold_workflow_lib)"
  [[ -n "$wf" ]] || { echo "scaffold: workflow.sh not found beside scaffold.sh" >&2; return 1; }
  while IFS=$'\t' read -r dest src _tier; do
    [[ -n "$dest" ]] || continue
    pfx="$(_scaffold_is_region_managed "$dest")"
    [[ -n "$pfx" ]] || continue
    [[ -f "$dest" && -f "$root/$src" ]] || continue
    # Not yet adopted (no markers) → the plain copy in the update's apply step
    # installs the marked template; merging here would duplicate every stage.
    if ! _scaffold_regions_adopted "$dest" "$pfx" "$wf"; then
      printf '%s\t%s\n' "$dest" '{"skipped":"no regions yet — replace whole-file"}'
      continue
    fi
    if verdict="$(bash "$wf" merge "$dest" "$root/$src" "$pfx" \
                  "$(scaffold_region_sums "$dest")" 2>/dev/null)"; then
      printf '%s\t%s\n' "$dest" "$verdict"
    else
      printf '%s\t%s\n' "$dest" '{"error":"corrupt markers — not merged"}'
    fi
  done < <(scaffold_manifest "$type")
  return 0
}

# --- CLI dispatch (skipped when sourced) --------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail
  cmd="${1:-status}"; shift || true
  case "$cmd" in
    manifest)    scaffold_manifest "$@" ;;
    status)      [[ $# -ge 1 ]] || { echo "scaffold: status needs a plugin root" >&2; exit 2; }
                 scaffold_status "$@" ;;
    summary)     [[ $# -ge 1 ]] || { echo "scaffold: summary needs a plugin root" >&2; exit 2; }
                 scaffold_summary "$@" ;;
    trace)       [[ $# -ge 3 ]] || { echo "scaffold: trace needs <dest> <src> <plugin-root>" >&2; exit 2; }
                 scaffold_trace "$@" ;;
    stamp)       [[ $# -ge 2 ]] || { echo "scaffold: stamp needs <plugin-root> <type>" >&2; exit 2; }
                 scaffold_write_stamp "$@" ;;
    integrity)   scaffold_integrity ;;
    merge-regions) [[ $# -ge 1 ]] || { echo "scaffold: merge-regions needs a plugin root" >&2; exit 2; }
                 scaffold_merge_regions "$@" ;;
    region-sums) [[ $# -ge 1 ]] || { echo "scaffold: region-sums needs a dest path" >&2; exit 2; }
                 scaffold_region_sums "$1" ;;
    keep)        [[ $# -ge 1 ]] || { echo "scaffold: keep needs at least one path" >&2; exit 2; }
                 scaffold_keep "$@" ;;
    version)     scaffold_field plugin_version ;;
    plugin-root) scaffold_plugin_root ;;
    *) echo "usage: scaffold.sh manifest|status|summary|stamp|version|plugin-root ..." >&2; exit 2 ;;
  esac
fi
