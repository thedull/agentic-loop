#!/usr/bin/env bash
# Review benches — one persistent, runnable checkout per OPEN PR.
#
# Why this exists (field evidence, 2026-07-26): the build stage's worktree is
# ephemeral by design and is cleaned after the blind review. That is correct
# for build isolation, but on projects where evening review means RUNNING the
# thing (`npm run app` onto hardware, launching a desktop app) it leaves an
# open PR with nothing to test from. A bench is the second, longer-lived
# artifact: the PR's branch checked out somewhere stable, already merged with
# the default branch, with project setup done.
#
# Reconcile, don't remember. The invariant — every `pr-open` spec has a fresh
# bench, every `done` spec has none — is checked and repaired mechanically on
# every factory iteration. An iteration that forgets is fixed by the next one.
# This is deliberately NOT an agent instruction: prose steps get skipped.
#
# Freshness is half the point (LEARNINGS, two strikes): a bench branched
# before a fix on main re-surfaces already-fixed bugs and burns a whole
# feedback round. Every bench is merged with current origin/<default> — and a
# non-trivial conflict ABORTS and reports rather than guessing.
#
# Config (.agentic/config.json, all optional):
#   "bench": { "enabled": true,
#              "dir": "../<repo>-benches",     # never inside the repo
#              "setup_cmd": "npm ci" }         # run once, at creation
# Env overrides: FACTORY_BENCH_DIR, FACTORY_BENCH_SETUP_CMD.
#
# CLI:
#   bench.sh reconcile        ensure benches for pr-open specs, remove for done
#   bench.sh list             one line per existing bench
#   bench.sh ensure <spec>    single spec file
#   bench.sh remove <slug>    remove one bench (refuses if it has edits)
#
# Exit 0 when the feature is off or nothing needs doing. Never fails the
# caller: a per-bench problem is reported and reconcile moves on.

set -uo pipefail

# shellcheck disable=SC1091
_bench_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_bench_lib_dir/obs.sh"      # obs_root, obs_event — sourced directly,
                                      # not relied on transitively via tracker.sh
source "$_bench_lib_dir/tracker.sh"  # tracker_list, _tracker_field

_bench_cfg() { # KEY DEFAULT — read .bench.<key> from the project config
  local v
  v="$(jq -r ".bench.$1 // empty" "$(obs_root)/config.json" 2>/dev/null)"
  [[ -n "$v" && "$v" != "null" ]] && printf '%s' "$v" || printf '%s' "$2"
}

bench_enabled() {
  [[ "$(jq -r '.bench.enabled // false' "$(obs_root)/config.json" \
        2>/dev/null)" == "true" ]]
}

# Default bench dir is a SIBLING of the repo: inside it would pollute
# git status and get walked by every tool that greps the tree.
_bench_dir() {
  local d root
  root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
  d="${FACTORY_BENCH_DIR:-$(_bench_cfg dir "")}"
  [[ -z "$d" ]] && d="../$(basename "$root")-benches"
  # absolutize relative to the repo root, not the cwd
  [[ "$d" == /* ]] || d="$root/$d"
  printf '%s' "$d"
}

_bench_default_branch() {
  git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null \
    | sed 's|^origin/||' || true
}

_bench_slug() { # BRANCH SPECFILE — slug from the branch, else the filename
  local branch="$1" spec="$2" slug
  slug="${branch##*/}"; slug="${slug#idea-}"
  if [[ -z "$slug" ]]; then
    slug="$(basename "$spec" .md)"; slug="${slug#*-}"
  fi
  printf '%s' "$slug"
}

_bench_obs() { # ACTION SLUG DETAIL_JSON
  obs_event bench bench "$(jq -cn --arg a "$1" --arg s "$2" \
    --argjson d "${3:-\{\}}" \
    '{detail: ({action: $a, slug: $s} + $d)}' 2>/dev/null || echo '{}')"
}

# bench_ensure SPECFILE — create/refresh the bench for one pr-open spec.
bench_ensure() {
  local spec="$1" branch slug dir path base created=0 setup
  branch="$(_tracker_field "$spec" branch)"
  if [[ -z "$branch" ]]; then
    echo "bench: $(basename "$spec") has no branch field — skipped" >&2
    return 0
  fi
  slug="$(_bench_slug "$branch" "$spec")"
  dir="$(_bench_dir)"; path="$dir/$slug"

  if [[ ! -d "$path" ]]; then
    mkdir -p "$dir"
    git fetch origin --quiet 2>/dev/null || true
    if ! git worktree add "$path" "$branch" >/dev/null 2>&1; then
      echo "bench: could not create worktree for $branch (already checked out elsewhere?)" >&2
      _bench_obs error "$slug" "$(jq -cn --arg b "$branch" '{branch:$b, reason:"worktree add failed"}')"
      return 0
    fi
    created=1
  fi

  # Freshness: merge current default branch, abort on any conflict.
  base="$(_bench_default_branch)"; base="${base:-main}"
  git -C "$path" fetch origin --quiet 2>/dev/null || true
  if ! git -C "$path" merge "origin/$base" --no-edit >/dev/null 2>&1; then
    git -C "$path" merge --abort 2>/dev/null || true
    echo "bench: $slug CONFLICTS with origin/$base — left un-merged, resolve by hand" >&2
    _bench_obs conflict "$slug" "$(jq -cn --arg b "$base" '{base:$b}')"
    return 0
  fi

  if [[ $created -eq 1 ]]; then
    setup="${FACTORY_BENCH_SETUP_CMD:-$(_bench_cfg setup_cmd "")}"
    if [[ -n "$setup" ]]; then
      ( cd "$path" && eval "$setup" ) >/dev/null 2>&1 \
        || echo "bench: setup_cmd failed in $slug (bench still usable)" >&2
    fi
    echo "bench: created $path" >&2
    _bench_obs created "$slug" "$(jq -cn --arg p "$path" '{path:$p}')"
  else
    _bench_obs refreshed "$slug" "$(jq -cn --arg p "$path" '{path:$p}')"
  fi
  return 0
}

# bench_remove SLUG — remove a bench, but never one with uncommitted work.
#
# TEST-PLAN.md is excluded from that check: the review stage drops it into the
# bench for hands-on testing, so counting it as "the user's uncommitted work"
# would make every bench permanently undeletable and the reconcile loop would
# silently stop cleaning up.
bench_remove() {
  local slug="$1" path dirty
  path="$(_bench_dir)/$slug"
  [[ -d "$path" ]] || return 0
  dirty="$(git -C "$path" status --porcelain 2>/dev/null \
           | grep -v '^?? TEST-PLAN\.md$' || true)"
  if [[ -n "$dirty" ]]; then
    echo "bench: $slug has uncommitted changes — kept (remove by hand when done)" >&2
    _bench_obs kept_dirty "$slug" '{}'
    return 0
  fi
  git worktree remove "$path" --force >/dev/null 2>&1 \
    || { rm -rf "$path"; git worktree prune >/dev/null 2>&1 || true; }
  echo "bench: removed $path" >&2
  _bench_obs removed "$slug" '{}'
  return 0
}

# Statuses whose benches should not exist: the PR is merged, or the spec left
# the queue. `done` alone is not enough — a spec that was pr-open and is then
# shelved or superseded belongs to NEITHER loop below, so its bench would leak
# forever: never refreshed, never removed, and quietly rotting against the
# freshness rule this file exists to enforce.
_BENCH_RETIRED_STATUSES="done shelved superseded"

# bench_reconcile — the invariant, enforced. Idempotent; safe every iteration.
bench_reconcile() {
  bench_enabled || return 0
  local f branch slug s
  while IFS= read -r f; do
    [[ -n "$f" ]] && bench_ensure "$f"
  done < <(tracker_list pr-open)
  for s in $_BENCH_RETIRED_STATUSES; do
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      branch="$(_tracker_field "$f" branch)"
      [[ -n "$branch" ]] || continue
      slug="$(_bench_slug "$branch" "$f")"
      bench_remove "$slug"
    done < <(tracker_list "$s")
  done
  return 0
}

bench_list() {
  local dir path
  dir="$(_bench_dir)"
  [[ -d "$dir" ]] || return 0
  for path in "$dir"/*/; do
    [[ -d "$path" ]] || continue
    printf '%s\t%s\n' "$(basename "$path")" \
      "$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-reconcile}"; shift || true
  case "$cmd" in
    reconcile) bench_reconcile ;;
    ensure)    bench_enabled || exit 0; bench_ensure "$@" ;;
    remove)    bench_remove "$@" ;;
    list)      bench_list ;;
    *) echo "usage: bench.sh reconcile|ensure <spec>|remove <slug>|list" >&2; exit 2 ;;
  esac
fi
