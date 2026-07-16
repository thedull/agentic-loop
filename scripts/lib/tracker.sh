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
#   id, title, status, profile, created, claimed_by, branch, pr
# Status state machine:
#   queued -> specd -> building -> built -> reviewing -> pr-open -> done
#   any state -> blocked (with reason recorded in the spec body's Caveats)
#
# Concurrency: claims are serialized through a mkdir lock (atomic on POSIX).
# Single-writer rule: whoever holds a claim is the only writer of that file.
#
# CLI usage (for skills; also sourceable as a library):
#   tracker.sh list <status>              print matching spec paths, oldest first
#   tracker.sh claim <from> <to> <actor>  claim oldest <from> item; prints its path
#   tracker.sh advance <file> <status> [key value]...   set status (+ extra fields)
#   tracker.sh next-id                    print next zero-padded id (e.g. 004)
#   tracker.sh report                     per-status counts + item lines

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

VALID_STATUSES="queued specd building built reviewing pr-open blocked done"

_tracker_die() { echo "tracker: $*" >&2; exit 2; }

_tracker_valid_status() {
  local s
  for s in $VALID_STATUSES; do [[ "$1" == "$s" ]] && return 0; done
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

# tracker_claim FROM TO ACTOR — atomically move the oldest FROM item to TO,
# recording the actor. Prints the claimed path; exits 1 if queue is empty.
tracker_claim() {
  local from="$1" to="$2" actor="$3" target
  _tracker_valid_status "$from" || _tracker_die "unknown status '$from'"
  _tracker_valid_status "$to"   || _tracker_die "unknown status '$to'"
  mkdir -p "$(dirname "$TRACKER_LOCK_DIR")"
  tracker_lock
  target="$(tracker_list "$from" | head -n 1 || true)"
  if [[ -z "$target" ]]; then
    tracker_unlock
    return 1
  fi
  _tracker_set_field "$target" status "$to"
  _tracker_set_field "$target" claimed_by "$actor"
  _tracker_set_field "$target" claimed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tracker_unlock
  _tracker_obs_transition "$target" "$from" "$to" "$actor"
  echo "$target"
}

# tracker_advance FILE STATUS [KEY VALUE]... — set status plus optional fields.
tracker_advance() {
  local file="$1" status="$2"; shift 2
  [[ -f "$file" ]] || _tracker_die "no such spec file: $file"
  _tracker_valid_status "$status" || _tracker_die "unknown status '$status'"
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

# tracker_report — per-status counts, then "status<TAB>id<TAB>title" lines.
tracker_report() {
  local s f count
  for s in $VALID_STATUSES; do
    count="$(tracker_list "$s" | wc -l | tr -d ' ')"
    [[ "$count" == "0" ]] || echo "$s: $count"
  done
  [[ -d "$FACTORY_SPECS_DIR" ]] || return 0
  for f in "$FACTORY_SPECS_DIR"/*.md; do
    [[ -e "$f" ]] || continue
    printf '%s\t%s\t%s\n' \
      "$(_tracker_field "$f" status)" \
      "$(_tracker_field "$f" id)" \
      "$(_tracker_field "$f" title)"
  done
}

# --- CLI dispatch (skipped when sourced) --------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    list)    tracker_list "$@" ;;
    claim)   tracker_claim "$@" ;;
    advance) tracker_advance "$@" ;;
    next-id) tracker_next_id ;;
    report)  tracker_report ;;
    *) _tracker_die "usage: tracker.sh list|claim|advance|next-id|report ..." ;;
  esac
fi
