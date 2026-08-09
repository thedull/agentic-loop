#!/usr/bin/env bash
# learnings.sh — the size discipline for LEARNINGS.md (spec 012).
#
# The cap was "~300 lines" in three prose files, enforced by a checkbox someone
# had to remember. This makes it readable, checkable, and — deliberately — only
# ever consolidated on purpose.
#
#   learnings.sh cap                    print the declared cap
#   learnings.sh check <file>           report; NEVER modifies. exit 2 = over cap
#   learnings.sh consolidate <file>     merge exact duplicates, PROPOSE the rest
#
# The split in `consolidate` is the whole design. Byte-identical entries are a
# decidable fact and are merged. "Near-duplicate" is a judgment, and this repo
# puts judgments in front of a reviewer, not inside a gate: a similarity
# threshold that silently merges destroys distinct learnings whenever it is
# wrong, and nothing afterwards can tell that it happened.
#
# No model is required or used. A consolidator that needs one cannot run in the
# place it is most needed — an unattended loop with the network down.

set -uo pipefail
LEARNINGS_CAP="${LEARNINGS_CAP:-300}"
_l_die() { echo "learnings: $1" >&2; exit 2; }

learnings_cap() { echo "$LEARNINGS_CAP"; }

learnings_check() {
  local f="${1:-}" n
  [[ -n "$f" && -f "$f" ]] || _l_die "usage: learnings.sh check <file>"
  n="$(wc -l < "$f" | tr -d ' ')"
  if [[ "$n" -gt "$LEARNINGS_CAP" ]]; then
    echo "learnings: $f is $n lines, over the cap of $LEARNINGS_CAP by $((n - LEARNINGS_CAP))" >&2
    echo "           run 'learnings.sh consolidate $f' deliberately — this check never rewrites" >&2
    return 2
  fi
  echo "learnings: $f is $n lines, clean (cap $LEARNINGS_CAP)"
}

# _l_key LINE — the comparable body of an entry, with the date stripped.
# Two entries are exact duplicates when their bodies match after whitespace
# normalisation; the date is metadata, not content.
_l_key() {
  printf '%s' "$1" \
    | sed -E 's/^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\][[:space:]]*//; s/^- \[[0-9]+\][[:space:]]*//' \
    | tr -s '[:space:]' ' ' \
    | sed -E 's/^ +| +$//g'
}
_l_date() { printf '%s' "$1" | sed -nE 's/^- \[([0-9]{4}-[0-9]{2}-[0-9]{2})\].*/\1/p'; }

learnings_consolidate() {
  local f="${1:-}" bak
  [[ -n "$f" && -f "$f" ]] || _l_die "usage: learnings.sh consolidate <file>"

  # Reversible without git: the sandbox this is tested in has none, and a
  # recovery path no case can exercise is a recovery path nobody can trust.
  bak="$f.$(date +%Y%m%d-%H%M%S).bak"
  cp "$f" "$bak"

  # Two parallel arrays: the line itself, and what it IS. No sentinel strings
  # are ever written into the data — an earlier version marked entry slots with
  # a literal "\000ENT:<i>" and silently dropped any real content line that
  # happened to match it. A file this rewrites is the project's memory; it does
  # not get to lose a line under any input.
  local -a lines=() kind=() keys=() dates=() bodies=()
  local line key d i found merged=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" != "- "* ]]; then
      lines+=("$line"); kind+=("raw"); continue
    fi
    key="$(_l_key "$line")"; d="$(_l_date "$line")"
    found=-1
    for i in "${!keys[@]}"; do [[ "${keys[$i]}" == "$key" ]] && { found=$i; break; }; done
    if [[ $found -ge 0 ]]; then
      merged=$((merged+1))
      # keep the EARLIEST date — a lesson dates from when it was first learned
      if [[ -n "$d" && ( -z "${dates[$found]}" || "$d" < "${dates[$found]}" ) ]]; then
        dates[$found]="$d"; bodies[$found]="$line"
      fi
      lines+=("$line"); kind+=("$found")
    else
      keys+=("$key"); dates+=("$d"); bodies+=("$line")
      lines+=("$line"); kind+=("$((${#keys[@]}-1))")
    fi
  done < "$f"

  # Emit. Every raw line passes through byte-for-byte; each entry index is
  # emitted once, at its first position, carrying the earliest date.
  local -a seen=()
  : > "$f"
  local n=0
  for line in ${lines[@]+"${lines[@]}"}; do
    if [[ "${kind[$n]}" == "raw" ]]; then
      printf '%s\n' "$line" >> "$f"
    else
      i="${kind[$n]}"
      if [[ -z "${seen[$i]:-}" ]]; then
        printf '%s\n' "$(printf '%s' "${bodies[$i]}" | sed -E "s/^- \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]/- [${dates[$i]:-}]/")" >> "$f"
        seen[$i]=1
      fi
    fi
    n=$((n+1))
  done

  # Near-duplicates: reported for a human to accept or reject. The file is NOT
  # changed on their account.
  local a b ka kb cand=0
  for ((i=0; i<${#keys[@]}; i++)); do
    for ((b=i+1; b<${#keys[@]}; b++)); do
      ka="${keys[$i]}"; kb="${keys[$b]}"
      [[ "$ka" == "$kb" ]] && continue
      # cheap, explainable similarity: shared word ratio over the shorter entry
      local shared total
      shared="$(printf '%s\n' $ka | sort -u > /tmp/.la$$; printf '%s\n' $kb | sort -u > /tmp/.lb$$; comm -12 /tmp/.la$$ /tmp/.lb$$ | wc -l | tr -d ' ')"
      total="$(wc -l < /tmp/.la$$ | tr -d ' ')"
      rm -f /tmp/.la$$ /tmp/.lb$$
      [[ "$total" -eq 0 ]] && continue
      if [[ $(( shared * 100 / total )) -ge 60 ]]; then
        [[ $cand -eq 0 ]] && echo "learnings: near-duplicate candidates — merge these by hand if you agree; nothing was changed on their account:" >&2
        cand=$((cand+1))
        echo "  candidate $cand:" >&2
        echo "    ${bodies[$i]}" >&2
        echo "    ${bodies[$b]}" >&2
      fi
    done
  done

  echo "learnings: merged $merged exact duplicate(s); $cand near-duplicate candidate(s) reported, not merged"
  echo "learnings: previous file preserved at $bak"
}

case "${1:-}" in
  cap)         shift; learnings_cap ;;
  check)       shift; learnings_check "$@" ;;
  consolidate) shift; learnings_consolidate "$@" ;;
  *) _l_die "usage: learnings.sh cap | check <file> | consolidate <file>" ;;
esac
