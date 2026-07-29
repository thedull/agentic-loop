#!/usr/bin/env bash
# Tracker interface for the factory's spec queue.
#
# This is the connector seam: every skill and workflow goes through these
# functions and NEVER touches spec-file frontmatter directly. The shipped
# backend is plain files + git (factory/specs/NNN-slug.md with a `status:`
# frontmatter field). A future GitHub Issues or Jira backend replaces the
# function bodies below without touching any caller.
#
# Spec file contract (frontmatter, one `key: value` per line, `---` fences):
#   id, title, status, profile, created, claimed_by, branch, pr,
#   depends_on (optional: space-separated spec ids, e.g. "003 005")
#   shelved_from, shelved_reason, shelved_at, restored_at  (see below)
#   superseded_by, superseded_reason, superseded_at
# Status state machine:
#   queued -> specd -> building -> built -> reviewing -> pr-open -> done
#   any state -> blocked     (stuck; reason in the spec body's Caveats)
#   any state -> shelved     (deprioritized; reversible via `restore`)
#   any state -> superseded  (the outcome landed some other way)
#
# The three off-ramps are NOT interchangeable and must not be collapsed:
#   blocked     needs a human to answer something; the spec still wants doing.
#   shelved     nobody is doing this now. Dependents STALL until rewired.
#   superseded  the outcome exists already (an external hotfix, another spec).
#               Dependents become claimable — but only against a VERIFIED
#               citation; see _tracker_supersede_lands.
# evals/mine.sh mines `blocked` transitions as failure signal, so routing a
# deliberate deprioritization through `blocked` would poison that signal.
#
# Dependencies: a spec with depends_on is only claimable once EVERY listed id
# is `done` (merged) or a VERIFIED `superseded`. built/pr-open do not count —
# unmerged work is not on main, so a dependent build could not see it (the
# exact failure observed in the field: dependents built against a base missing
# their dependency). Ids matching no spec count as unmet — a typo shows up in
# `report` as a perpetual `waits:` rather than silently passing. Dep-waiting
# specs are not `blocked`; they simply stay put until claimable.
#
# Gated statuses: `shelved` and `superseded` are reachable ONLY through
# tracker.sh shelve/supersede, and `advance` will not move a spec back OUT of
# them. Both directions matter — see _tracker_gated_status.
#
# Concurrency: claims are serialized through a mkdir lock (atomic on POSIX).
# Single-writer rule: whoever holds a claim is the only writer of that file.
#
# CLI usage (for skills; also sourceable as a library):
#   tracker.sh list <status>              print matching spec paths, oldest first
#   tracker.sh claim <from> <to> <actor>  claim oldest <from> item whose
#                                         depends_on are all done; prints its path
#   tracker.sh advance <file> <status> [key value]...   set status (+ extra fields)
#   tracker.sh next-id                    print next zero-padded id (e.g. 004)
#   tracker.sh report                     per-status counts + item lines
#                                         (dep-waiting items gain "waits: <ids>",
#                                          dead chains also "stalled: <ids>")
#   tracker.sh field <file> <key>         print one frontmatter value
#   tracker.sh shelve <file> <actor> [reason]        deprioritize (reversible)
#   tracker.sh restore <file> <actor>                undo a shelve
#   tracker.sh supersede <file> <actor> <ref> [reason]  outcome landed elsewhere
#   tracker.sh dependents <id> [--transitive]        reverse dependency lookup
#   tracker.sh dep-drop <file> <id>                  remove one depends_on id
#   tracker.sh dep-replace <file> <old> <new>        re-point one depends_on id
#
# Exit codes: 0 ok · 1 `claim` found nothing claimable · 2 usage/hard error
#             3 `shelve`/`supersede` refused — the spec is mid-stage
#               (building/reviewing); re-run with TRACKER_FORCE_LIVE=1 to
#               override deliberately.

set -euo pipefail

# Opt-in observability (no-op unless enabled — see obs.sh).
# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/obs.sh"

# _tracker_obs_transition FILE FROM TO ACTOR — one tracker_transition event.
_tracker_obs_transition() {
  obs_event tracker_transition tracker "$(jq -cn \
    --arg f "$1" --arg from "$2" --arg to "$3" --arg actor "$4" '
    {status: (if $to == "blocked" then "blocked" else null end),
     detail: {spec_file: $f, from_status: (if $from == "" then null else $from end),
              to_status: $to, actor: (if $actor == "" then null else $actor end)}}' \
    2>/dev/null || echo '{}')"
}

FACTORY_SPECS_DIR="${FACTORY_SPECS_DIR:-factory/specs}"
TRACKER_LOCK_DIR="${TRACKER_LOCK_DIR:-.agentic/tracker.lock}"
TRACKER_LOCK_TIMEOUT="${TRACKER_LOCK_TIMEOUT:-30}"

VALID_STATUSES="queued specd building built reviewing pr-open blocked shelved superseded done"

# Statuses that carry bookkeeping which a plain `advance` would not write.
# Reaching one without that bookkeeping produces a record that cannot be
# reversed (a shelve with no shelved_from) or that unblocks dependents on an
# unchecked claim (a supersede with no citation) — so both are gated.
_TRACKER_GATED_STATUSES="shelved superseded"

# Statuses a stage may legitimately be mid-write on. Shelving one risks
# racing an unattended agent that is about to advance the very same file.
_TRACKER_LIVE_STATUSES="building reviewing"

_tracker_die() { echo "tracker: $*" >&2; exit 2; }

_tracker_valid_status() {
  local s
  for s in $VALID_STATUSES; do [[ "$1" == "$s" ]] && return 0; done
  return 1
}

_tracker_gated_status() {
  local s
  for s in $_TRACKER_GATED_STATUSES; do [[ "$1" == "$s" ]] && return 0; done
  return 1
}

_tracker_live_status() {
  local s
  for s in $_TRACKER_LIVE_STATUSES; do [[ "$1" == "$s" ]] && return 0; done
  return 1
}

# _tracker_field FILE KEY — print the frontmatter value for KEY (empty if unset).
_tracker_field() {
  awk -v key="$2" '
    NR==1 && $0=="---" { infm=1; next }
    infm && $0=="---"  { exit }
    infm && index($0, key ": ")==1 { print substr($0, length(key)+3); exit }
  ' "$1"
}

# _tracker_set_field FILE KEY VALUE — set (or append) a frontmatter field in place.
_tracker_set_field() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "${file}.XXXXXX")"
  awk -v key="$2" -v value="$3" '
    NR==1 && $0=="---" { infm=1; print; next }
    infm && $0=="---"  {
      if (!done) { print key ": " value }
      infm=0; print; next
    }
    infm && index($0, key ":")==1 { print key ": " value; done=1; next }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

tracker_lock() {
  local waited=0
  until mkdir "$TRACKER_LOCK_DIR" 2>/dev/null; do
    sleep 1
    waited=$((waited + 1))
    if [[ $waited -ge $TRACKER_LOCK_TIMEOUT ]]; then
      _tracker_die "could not acquire lock $TRACKER_LOCK_DIR after ${TRACKER_LOCK_TIMEOUT}s (stale? rmdir it if no factory run is live)"
    fi
  done
}

tracker_unlock() { rmdir "$TRACKER_LOCK_DIR" 2>/dev/null || true; }

# tracker_list STATUS — spec paths with that status, oldest (lowest id) first.
tracker_list() {
  local status="$1" f
  _tracker_valid_status "$status" || _tracker_die "unknown status '$status'"
  [[ -d "$FACTORY_SPECS_DIR" ]] || return 0
  # if-fi, not `&&`: a trailing false `&&` would propagate exit 1 through the
  # pipeline and, under set -e, kill a caller holding the claim lock.
  for f in "$FACTORY_SPECS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    if [[ "$(_tracker_field "$f" status)" == "$status" ]]; then echo "$f"; fi
  done | sort
  return 0
}

# _tracker_file_for_id ID — path of the spec with that id (empty if none).
_tracker_file_for_id() {
  local id="$1" f
  [[ -d "$FACTORY_SPECS_DIR" ]] || return 0
  for f in "$FACTORY_SPECS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    if [[ "$(_tracker_field "$f" id)" == "$id" ]]; then printf '%s' "$f"; return 0; fi
  done
  return 0
}

# _tracker_supersede_lands FILE — true only if FILE's `superseded_by` citation
# provably resolves to work already on the default branch.
#
# The status alone is NEVER trusted. Marking a spec superseded when the work
# did not actually land recreates the exact field failure this file's header
# describes: dependents building against a base missing their dependency. A
# citation that cannot be checked (empty, unresolvable, not yet merged, or a
# spec that is not itself done) is treated as unmet — fail closed, the same
# posture as an unknown dependency id.
#
# Two citation forms:
#   spec id     e.g. "003"  — satisfied only if spec 003 is `done`
#   commit-ish  e.g. a sha  — satisfied only if it is an ancestor of the tip
#
# NOT supported in v1: chaining through another `superseded` spec. Rare, and
# the recursion is a hazard nobody has needed yet — such a citation reads as
# unmet and shows up in `report` as `stalled:`.
_tracker_supersede_lands() {
  local file="$1" ref target base
  ref="$(_tracker_field "$file" superseded_by)"
  [[ -n "$ref" ]] || return 1
  # Every exit below is an explicit `return`: a bare failing test as the last
  # command of a function is an errexit landmine for any caller that is not
  # in a condition context.
  if [[ "$ref" =~ ^[0-9]+$ ]]; then
    target="$(_tracker_file_for_id "$ref")"
    [[ -n "$target" ]] || return 1
    if [[ "$(_tracker_field "$target" status)" == "done" ]]; then return 0; fi
    return 1
  fi
  git rev-parse --verify --quiet "${ref}^{commit}" >/dev/null 2>&1 || return 1
  base="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  [[ -n "$base" ]] || base="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"
  [[ -n "$base" ]] || base="main"
  if git merge-base --is-ancestor "$ref" "$base" 2>/dev/null; then return 0; fi
  return 1
}

# _tracker_dep_met FILE_OF_DEP — is this dependency satisfied?
_tracker_dep_met() {
  local target="$1" status
  [[ -n "$target" ]] || return 1
  status="$(_tracker_field "$target" status)"
  [[ "$status" == "done" ]] && return 0
  if [[ "$status" == "superseded" ]] && _tracker_supersede_lands "$target"; then
    return 0
  fi
  return 1
}

# _tracker_unmet FILE — print the space-separated depends_on ids that are not
# satisfied (ids matching no spec count as unmet). Empty output = claimable.
_tracker_unmet() {
  local file="$1" deps dep out=""
  deps="$(_tracker_field "$file" depends_on)"
  [[ -z "$deps" ]] && return 0
  for dep in $deps; do
    _tracker_dep_met "$(_tracker_file_for_id "$dep")" || out="${out:+$out }$dep"
  done
  printf '%s' "$out"
  return 0
}

# _tracker_dep_dead ID — true when this unmet dependency cannot clear through
# ordinary factory progress and needs a human to rewire the chain: no such
# spec (a typo), a `shelved` spec, or a `superseded` one whose citation does
# not verify. Anything else unmet is merely in flight.
_tracker_dep_dead() {
  local target status
  target="$(_tracker_file_for_id "$1")"
  [[ -n "$target" ]] || return 0
  status="$(_tracker_field "$target" status)"
  [[ "$status" == "shelved" ]] && return 0
  [[ "$status" == "superseded" ]] && ! _tracker_supersede_lands "$target" && return 0
  return 1
}

# tracker_claim FROM TO ACTOR — atomically move the oldest FROM item whose
# depends_on are all done to TO, recording the actor. Dep-waiting items are
# passed over (and logged as a tracker_skip event), not blocked. Prints the
# claimed path; exits 1 if nothing is claimable (empty queue or all waiting).
tracker_claim() {
  local from="$1" to="$2" actor="$3" target="" f
  local -a skipped=()
  _tracker_valid_status "$from" || _tracker_die "unknown status '$from'"
  _tracker_valid_status "$to"   || _tracker_die "unknown status '$to'"
  _tracker_gated_status "$to" && _tracker_die \
    "'$to' can only be set via tracker.sh shelve/supersede"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if [[ -z "$(_tracker_unmet "$f")" ]]; then
      target="$f"
      break
    fi
    skipped+=("$(basename "$f")")
  done < <(tracker_list "$from")
  if [[ -z "$target" ]]; then
    tracker_unlock
    if [[ ${#skipped[@]} -gt 0 ]]; then
      _tracker_obs_skip "$from" "$actor" "${skipped[@]}"
      echo "tracker: nothing claimable — ${#skipped[@]} $from item(s) waiting on depends_on" >&2
    fi
    return 1
  fi
  _tracker_set_field "$target" status "$to"
  _tracker_set_field "$target" claimed_by "$actor"
  _tracker_set_field "$target" claimed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tracker_unlock
  [[ ${#skipped[@]} -gt 0 ]] && _tracker_obs_skip "$from" "$actor" "${skipped[@]}"
  _tracker_obs_transition "$target" "$from" "$to" "$actor"
  echo "$target"
}

# _tracker_obs_skip FROM ACTOR SKIPPED... — one tracker_skip event naming the
# dep-waiting specs a claim passed over (mineable: dependency-stall frequency).
_tracker_obs_skip() {
  local from="$1" actor="$2"; shift 2
  obs_event tracker_skip tracker "$(jq -cn \
    --arg from "$from" --arg actor "$actor" \
    --argjson skipped "$(printf '%s\n' "$@" | jq -R . | jq -cs .)" '
    {detail: {reason: "depends_on unmet", from_status: $from,
              skipped: $skipped, actor: $actor}}' \
    2>/dev/null || echo '{}')"
}

# tracker_advance FILE STATUS [KEY VALUE]... — set status plus optional fields.
#
# Two guards, both about the gated statuses:
#
#   IN  — `advance <file> shelved` would write a status with none of the
#         bookkeeping `restore` needs, leaving the spec permanently stuck.
#   OUT — a human shelves a spec that a stage is still running on; that stage
#         finishes and calls `advance <file> built`, silently reverting the
#         human's decision with no trace at all. Refusing turns that race into
#         a visible failure the returning agent has to stop on.
tracker_advance() {
  local file="$1" status="$2"; shift 2
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  _tracker_valid_status "$status" || _tracker_die "unknown status '$status'"
  _tracker_gated_status "$status" && _tracker_die \
    "'$status' can only be set via tracker.sh shelve/supersede (they record the bookkeeping restore depends on)"
  local cur
  cur="$(_tracker_field "$file" status)"
  if _tracker_gated_status "$cur" && [[ "${TRACKER_FORCE_LIVE:-0}" != "1" ]]; then
    _tracker_die "$file is '$cur' — someone took it out of the queue while this stage ran. Stop and report; do not retry. (TRACKER_FORCE_LIVE=1 overrides.)"
  fi
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  local prev
  prev="$(_tracker_field "$file" status)"
  _tracker_set_field "$file" status "$status"
  while [[ $# -ge 2 ]]; do
    _tracker_set_field "$file" "$1" "$2"
    shift 2
  done
  tracker_unlock
  _tracker_obs_transition "$file" "$prev" "$status" \
    "$(_tracker_field "$file" claimed_by)"
}

# tracker_shelve FILE ACTOR [REASON] — take a spec out of the queue, keeping
# everything needed to put it back. Deliberately touches ONLY the shelve
# bookkeeping: `branch`, `pr`, `claimed_by` and `claimed_at` survive untouched,
# which is what makes a shelve/restore round trip on a pr-open spec exact.
#
# Refuses with exit 3 while the spec is mid-stage — an unattended agent may be
# writing this very file. TRACKER_FORCE_LIVE=1 overrides deliberately.
tracker_shelve() {
  local file="$1" actor="${2:-}" reason="${3:-}" prev
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  prev="$(_tracker_field "$file" status)"
  if [[ "$prev" == "shelved" ]]; then
    tracker_unlock
    _tracker_die "$file is already shelved — restore it first"
  fi
  if _tracker_live_status "$prev" && [[ "${TRACKER_FORCE_LIVE:-0}" != "1" ]]; then
    tracker_unlock
    echo "tracker: $file is '$prev' — a stage may be writing it right now." >&2
    echo "tracker: let the run finish, or re-run with TRACKER_FORCE_LIVE=1 to shelve anyway." >&2
    return 3
  fi
  _tracker_set_field "$file" status shelved
  _tracker_set_field "$file" shelved_from "$prev"
  _tracker_set_field "$file" shelved_reason "$reason"
  _tracker_set_field "$file" shelved_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tracker_unlock
  _tracker_obs_transition "$file" "$prev" shelved "$actor"
  echo "$file"
}

# tracker_restore FILE ACTOR — undo a shelve, returning the spec to whatever
# status it held before. Writes the status field directly rather than going
# through tracker_advance, which refuses to move anything out of `shelved`.
tracker_restore() {
  local file="$1" actor="${2:-}" cur target
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  cur="$(_tracker_field "$file" status)"
  target="$(_tracker_field "$file" shelved_from)"
  if [[ "$cur" != "shelved" ]]; then
    tracker_unlock
    _tracker_die "$file is '$cur', not shelved — nothing to restore"
  fi
  if [[ -z "$target" ]]; then
    tracker_unlock
    _tracker_die "$file has no shelved_from — cannot tell where it belongs (set status by hand)"
  fi
  if ! _tracker_valid_status "$target"; then
    tracker_unlock
    _tracker_die "corrupt shelved_from '$target' in $file"
  fi
  _tracker_set_field "$file" status "$target"
  _tracker_set_field "$file" shelved_from ""
  _tracker_set_field "$file" restored_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tracker_unlock
  _tracker_obs_transition "$file" shelved "$target" "$actor"
  echo "$file"
}

# tracker_supersede FILE ACTOR REF [REASON] — the outcome landed some other
# way. REF is mandatory: it is the citation that dependents are unblocked
# against, and _tracker_supersede_lands checks it rather than trusting it.
#
# An unverifiable CITATION is never refused — the claim may be true but
# uncheckable from here (a fix in another repo). What it does NOT do is
# unblock anyone; that is reported, loudly, on stderr.
#
# A live STAGE is refused, exactly as in tracker_shelve (exit 3). Both take a
# spec out of the queue, so both can yank a file an unattended agent is
# mid-write on; gating only one of them left a spec that read `building`
# superseded with no confirmation at all.
tracker_supersede() {
  local file="$1" actor="${2:-}" ref="${3:-}" reason="${4:-}" prev
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  [[ -n "$ref" ]] || _tracker_die \
    "supersede needs a REF — the spec id or commit-ish proving the work landed"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  prev="$(_tracker_field "$file" status)"
  if _tracker_live_status "$prev" && [[ "${TRACKER_FORCE_LIVE:-0}" != "1" ]]; then
    tracker_unlock
    echo "tracker: $file is '$prev' — a stage may be writing it right now." >&2
    echo "tracker: let the run finish, or re-run with TRACKER_FORCE_LIVE=1 to supersede anyway." >&2
    return 3
  fi
  _tracker_set_field "$file" status superseded
  _tracker_set_field "$file" superseded_by "$ref"
  _tracker_set_field "$file" superseded_reason "$reason"
  _tracker_set_field "$file" superseded_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tracker_unlock
  _tracker_obs_transition "$file" "$prev" superseded "$actor"
  echo "$file"
  if ! _tracker_supersede_lands "$file"; then
    echo "tracker: warning — '$ref' does not verifiably land on the default branch;" >&2
    echo "tracker: dependents of $(_tracker_field "$file" id) stay stalled until it does." >&2
  fi
  return 0
}

# tracker_dependents ID [--transitive] — which specs depend on ID.
# TSV: path<TAB>id<TAB>status<TAB>depth<TAB>via   (empty output = none)
# Deduped by path, so a diamond graph reports each affected spec once.
tracker_dependents() {
  local root="$1" mode="${2:-}"
  [[ -d "$FACTORY_SPECS_DIR" ]] || return 0
  local -a q_id=("$root") q_depth=(0) seen=("$root") printed=()
  local qi=0 cur depth f deps d fid p dup
  while [[ $qi -lt ${#q_id[@]} ]]; do
    cur="${q_id[$qi]}"; depth="${q_depth[$qi]}"; qi=$((qi + 1))
    for f in "$FACTORY_SPECS_DIR"/*.md; do
      [[ -e "$f" ]] || continue
      deps="$(_tracker_field "$f" depends_on)"
      [[ -n "$deps" ]] || continue
      for d in $deps; do
        [[ "$d" == "$cur" ]] || continue
        fid="$(_tracker_field "$f" id)"
        dup=0
        for p in ${printed[@]+"${printed[@]}"}; do
          [[ "$p" == "$f" ]] && { dup=1; break; }
        done
        if [[ $dup -eq 0 ]]; then
          printed+=("$f")
          printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$fid" \
            "$(_tracker_field "$f" status)" "$((depth + 1))" "$cur"
        fi
        if [[ "$mode" == "--transitive" ]]; then
          dup=0
          for p in ${seen[@]+"${seen[@]}"}; do
            [[ "$p" == "$fid" ]] && { dup=1; break; }
          done
          if [[ $dup -eq 0 ]]; then
            seen+=("$fid"); q_id+=("$fid"); q_depth+=("$((depth + 1))")
          fi
        fi
        break
      done
    done
  done
  return 0
}

# tracker_dep_drop FILE ID — remove one id from FILE's depends_on.
tracker_dep_drop() {
  local file="$1" id="$2" deps d out=""
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  deps="$(_tracker_field "$file" depends_on)"
  for d in $deps; do
    [[ "$d" == "$id" ]] || out="${out:+$out }$d"
  done
  _tracker_set_field "$file" depends_on "$out"
  tracker_unlock
  _tracker_obs_rewire "$file" drop "$id" ""
}

# tracker_dep_replace FILE OLD NEW — re-point one dependency. Dies if OLD is
# not actually there: silently doing nothing is how a rewire gets believed.
tracker_dep_replace() {
  local file="$1" old="$2" new="$3" deps d out="" found=0
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  [[ -n "$new" ]] || _tracker_die "dep-replace needs a replacement id"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  deps="$(_tracker_field "$file" depends_on)"
  for d in $deps; do
    if [[ "$d" == "$old" ]]; then
      found=1; out="${out:+$out }$new"
    else
      out="${out:+$out }$d"
    fi
  done
  if [[ $found -eq 0 ]]; then
    tracker_unlock
    _tracker_die "$file does not depend on '$old' — nothing to replace"
  fi
  _tracker_set_field "$file" depends_on "$out"
  tracker_unlock
  _tracker_obs_rewire "$file" replace "$old" "$new"
}

# _tracker_obs_rewire FILE ACTION OLD NEW — dependency-graph edits are mined
# to see how often shelving breaks chains.
_tracker_obs_rewire() {
  obs_event tracker_dep_rewire tracker "$(jq -cn \
    --arg f "$1" --arg a "$2" --arg old "$3" --arg new "$4" '
    {detail: {spec_file: $f, action: $a,
              old: (if $old == "" then null else $old end),
              new: (if $new == "" then null else $new end)}}' \
    2>/dev/null || echo '{}')"
}

# tracker_next_id — next zero-padded numeric id from existing filenames.
tracker_next_id() {
  local max=0 f base n
  if [[ -d "$FACTORY_SPECS_DIR" ]]; then
    for f in "$FACTORY_SPECS_DIR"/*.md; do
      [[ -e "$f" ]] || continue
      base="$(basename "$f")"
      n="${base%%-*}"
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      n=$((10#$n))
      [[ $n -gt $max ]] && max=$n
    done
  fi
  printf '%03d\n' $((max + 1))
}

# tracker_report — per-status counts, then "status<TAB>id<TAB>title" lines;
# items with unmet depends_on gain a trailing "waits: <ids>" column, and any
# whose wait can never clear on its own gain a further "stalled: <ids>".
#
# `waits:` keeps its exact original meaning — ALL unmet ids — so anything
# parsing it still works. `stalled:` names the subset that needs a human to
# rewire the chain (dependency shelved, superseded-but-unverified, or a typo).
# Without the split, a chain killed by a shelve looks identical to one that is
# simply still in progress, which is precisely how it would go unnoticed.
tracker_report() {
  local s f count unmet d dead
  for s in $VALID_STATUSES; do
    count="$(tracker_list "$s" | wc -l | tr -d ' ')"
    [[ "$count" == "0" ]] || echo "$s: $count"
  done
  [[ -d "$FACTORY_SPECS_DIR" ]] || return 0
  for f in "$FACTORY_SPECS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    unmet="$(_tracker_unmet "$f")"
    dead=""
    for d in $unmet; do
      _tracker_dep_dead "$d" && dead="${dead:+$dead }$d"
    done
    printf '%s\t%s\t%s%s%s\n' \
      "$(_tracker_field "$f" status)" \
      "$(_tracker_field "$f" id)" \
      "$(_tracker_field "$f" title)" \
      "${unmet:+	waits: $unmet}" \
      "${dead:+	stalled: $dead}"
  done
}

# --- CLI dispatch (skipped when sourced) --------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    list)        tracker_list "$@" ;;
    claim)       tracker_claim "$@" ;;
    advance)     tracker_advance "$@" ;;
    next-id)     tracker_next_id ;;
    report)      tracker_report ;;
    field)       _tracker_field "$@" ;;
    shelve)      tracker_shelve "$@" ;;
    restore)     tracker_restore "$@" ;;
    supersede)   tracker_supersede "$@" ;;
    dependents)  tracker_dependents "$@" ;;
    dep-drop)    tracker_dep_drop "$@" ;;
    dep-replace) tracker_dep_replace "$@" ;;
    *) _tracker_die "usage: tracker.sh list|claim|advance|next-id|report|field|shelve|restore|supersede|dependents|dep-drop|dep-replace ..." ;;
  esac
fi
