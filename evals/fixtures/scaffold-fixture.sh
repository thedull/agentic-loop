# scaffold-fixture.sh — helpers for evals/cases/scaffold/*.
# Sourced by a bash-unit case's $cmd; cwd is the eval's mktemp sandbox.
#
# The manifest in scaffold.sh is the real one, so a fake plugin root that
# ships only a couple of its files exercises exactly those: scaffold_status
# skips manifest entries the root does not carry.

# scaffold_fake_plugin DIR VERSION — a minimal plugin root.
scaffold_fake_plugin() {
  mkdir -p "$1/.claude-plugin"
  printf '{"name":"agentic-loop","version":"%s"}\n' "$2" \
    > "$1/.claude-plugin/plugin.json"
}

# scaffold_put PATH CONTENT — write a file, creating parents.
scaffold_put() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

# scaffold_fake_stamp STAMP_PATH VERSION TYPE [DEST...] — a stamp whose
# checksums are those of DEST files AS THEY CURRENTLY ARE on disk (i.e. it
# asserts "this is what was installed"). Call it before mutating a file to
# simulate a local edit, or after to simulate an untouched stale copy.
scaffold_fake_stamp() {
  local stamp="$1" version="$2" type="$3"; shift 3
  local sums="{}" d s
  for d in "$@"; do
    s="$(scaffold_checksum "$d")"
    [[ -n "$s" ]] || continue
    sums="$(printf '%s' "$sums" | jq -c --arg f "$d" --arg s "$s" '.[$f] = $s')"
  done
  mkdir -p "$(dirname "$stamp")"
  jq -n --arg v "$version" --arg t "$type" --argjson sums "$sums" \
    '{plugin_version: $v, project_type: $t, source: "fixture",
      updated_at: "2026-01-01T00:00:00Z", checksums: $sums}' > "$stamp"
}
