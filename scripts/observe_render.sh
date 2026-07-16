#!/usr/bin/env bash
# observe_render.sh — turn the observability event log into a report.
#
#   ./scripts/observe_render.sh                 # HTML for the latest run
#   ./scripts/observe_render.sh --run <id>      # specific run
#   ./scripts/observe_render.sh --tty           # terminal tree instead
#   ./scripts/observe_render.sh --summarize     # fill missing summaries via
#                                               # local Ollama (free; skipped
#                                               # silently if not running)
#   ./scripts/observe_render.sh --out FILE      # HTML output path
#
# Reads .agentic/observability/events-*.jsonl (schema v1). Subscription tiers
# show tokens, never invented dollars; only metered costs are summed as $.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OBS_DIR=".agentic/observability"
RUN_ID=""
OUT=""
MODE="html"
SUMMARIZE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run)       RUN_ID="$2"; shift 2 ;;
    --out)       OUT="$2"; shift 2 ;;
    --tty)       MODE="tty"; shift ;;
    --summarize) SUMMARIZE=1; shift ;;
    *) echo "error: unknown flag $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "error: jq not found" >&2; exit 3; }
ls "$OBS_DIR"/events-*.jsonl >/dev/null 2>&1 || {
  echo "error: no event log under $OBS_DIR — enable observability first" >&2
  echo "  (/agentic-loop:config observability on, then run something)" >&2
  exit 2
}

# Latest run = run_id of the last event in the newest file.
if [[ -z "$RUN_ID" ]]; then
  LATEST_FILE="$(ls -t "$OBS_DIR"/events-*.jsonl | head -1)"
  RUN_ID="$(tail -1 "$LATEST_FILE" | jq -r '.run_id // empty')"
  [[ -n "$RUN_ID" ]] || { echo "error: could not determine latest run id" >&2; exit 2; }
fi

EVENTS="$(cat "$OBS_DIR"/events-*.jsonl \
          | jq -c --arg rid "$RUN_ID" 'select(.run_id == $rid)')"
[[ -n "$EVENTS" ]] || { echo "error: no events for run '$RUN_ID'" >&2; exit 2; }

SUMMARY="$(printf '%s\n' "$EVENTS" | jq -s -f "$SCRIPT_DIR/lib/obs_summary.jq")"

# --- optional: fill missing summaries via local Ollama (never metered) -------
if [[ $SUMMARIZE -eq 1 && -x "$SCRIPT_DIR/call_ollama.sh" ]]; then
  if curl -sS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    TMP_EV="$(mktemp)"; trap 'rm -f "$TMP_EV"' EXIT
    # At most 10 nodes, root level only — this is a fallback, not a rewrite.
    while IFS= read -r idx; do
      NODE="$(printf '%s' "$SUMMARY" | jq -c ".nodes[$idx]")"
      printf '%s' "$NODE" > "$TMP_EV"
      # AGENTIC_OBSERVE=0: the renderer must not log its own telemetry calls.
      GEN="$(AGENTIC_OBSERVE=0 "$SCRIPT_DIR/call_ollama.sh" \
               --objective "Summarize in at most 25 words what this agent operation did, based on the JSON record" \
               --input-path "$TMP_EV" \
               --output-spec "one plain sentence, no preamble" 2>/dev/null \
             | jq -r 'if .status == "ok" then (.result | tostring | .[0:200]) else empty end')" || GEN=""
      [[ -n "$GEN" ]] && SUMMARY="$(printf '%s' "$SUMMARY" \
        | jq --argjson i "$idx" --arg s "$GEN" '.nodes[$i].summary = ("(ollama) " + $s)')"
    done < <(printf '%s' "$SUMMARY" \
             | jq -r '.nodes | to_entries
                      | map(select(.value.summary == null)) | .[0:10] | .[].key')
  else
    echo "note: --summarize skipped (ollama not responding on :11434)" >&2
  fi
fi

# --- tty ----------------------------------------------------------------------
if [[ "$MODE" == "tty" ]]; then
  printf '%s' "$SUMMARY" | jq -r '
    def ktok: if . == null then "?" elif . >= 10000 then ((. / 1000 | floor | tostring) + "k")
              elif . >= 1000 then ((. / 100 | floor / 10 | tostring) + "k")
              else tostring end;
    def dur: if . == null then "?"
             elif . < 1000 then (tostring + "ms")
             elif . < 60000 then ((. / 1000 | floor | tostring) + "s")
             else ((. / 60000 | floor | tostring) + "m" + (. % 60000 / 1000 | floor | tostring) + "s") end;
    def cost: if . == null or . == 0 then "" else " · $" + (. * 10000 | round / 10000 | tostring) end;
    def line: "[" + (.tier // "?") + "] "
              + ((.usage.input_tokens) | ktok) + "→" + ((.usage.output_tokens) | ktok) + " tok · "
              + (.duration_ms | dur) + (.est_cost_usd | cost) + " · " + (.status // "-")
              + (if .summary then " — \"" + (.summary | gsub("\n"; " ") | .[0:70]) + "\"" else "" end);
    "run " + .run_id + " · " + (.wall_ms | dur) + " · "
      + (.totals.input_tokens | ktok) + "→" + (.totals.output_tokens | ktok) + " tok · $"
      + (.totals.metered_cost_usd * 10000 | round / 10000 | tostring) + " metered · "
      + (.totals.errors | tostring) + " errors",
    (.nodes[] as $n
     | (if ($n.kind | IN("tracker_transition","gate","feature_toggle","missing_dependency"))
        then "├─ ◆ " + $n.label + (if $n.summary then " — " + $n.summary else "" end)
        else "├─ " + $n.label + (if $n.heuristic then " (heuristic)" else "" end) + " " + ($n | line)
        end),
       ($n.children[]? | "│   └─ " + .label + " (heuristic) " + line))
  '
  exit 0
fi

# --- html ----------------------------------------------------------------------
[[ -n "$OUT" ]] || { mkdir -p "$OBS_DIR/reports"; OUT="$OBS_DIR/reports/run-$RUN_ID.html"; }
mkdir -p "$(dirname "$OUT")"

# Template is split around the data blob so the JSON never passes through
# shell interpolation or awk replacement.
cat > "$OUT" <<'HTML_HEAD'
<!doctype html>
<meta charset="utf-8">
<title>agentic-loop run report</title>
<style>
  :root { --bg:#fff; --fg:#1a1a1a; --muted:#667; --line:#d8dce3; --card:#f5f7fa;
          --ok:#0a7d33; --err:#c0392b; --warn:#b26a00; --accent:#2456c4; }
  @media (prefers-color-scheme: dark) {
    :root { --bg:#14161a; --fg:#e6e8eb; --muted:#98a0ab; --line:#2c3138;
            --card:#1d2126; --ok:#4cc274; --err:#e06c5c; --warn:#d99a3d; --accent:#7ba3f0; }
  }
  body { background:var(--bg); color:var(--fg);
         font:14px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace;
         max-width:960px; margin:2rem auto; padding:0 1rem; }
  h1 { font-size:1.15rem; } .muted { color:var(--muted); }
  .totals { display:flex; flex-wrap:wrap; gap:.6rem; margin:1rem 0 1.4rem; }
  .totals div { background:var(--card); border:1px solid var(--line);
                border-radius:8px; padding:.45rem .8rem; }
  .totals b { display:block; font-size:1.05rem; }
  details { border-left:2px solid var(--line); margin:.35rem 0 .35rem .2rem;
            padding-left:.8rem; }
  details.heuristic { border-left-style:dashed; }
  summary { cursor:pointer; list-style:none; }
  summary::-webkit-details-marker { display:none; }
  .badge { display:inline-block; border:1px solid var(--line); border-radius:6px;
           padding:0 .45rem; margin-left:.4rem; font-size:.85em; color:var(--muted); }
  .badge.tier { color:var(--accent); border-color:var(--accent); }
  .st-ok { color:var(--ok); } .st-error,.st-blocked { color:var(--err); }
  .st-partial,.st-needs_escalation,.st-needs_input,.st-postponed,.st-running { color:var(--warn); }
  .nsummary { color:var(--muted); margin:.15rem 0 .2rem; white-space:pre-wrap; }
  .mark { color:var(--muted); font-style:italic; margin:.35rem 0 .35rem 1rem; }
</style>
<h1>agentic-loop run <span id="rid"></span></h1>
<div class="totals" id="totals"></div>
<div id="tree"></div>
<p class="muted" style="margin-top:2rem">Dashed nodes: shim calls attached by
time-overlap heuristic, not verified parentage. Subscription tiers show tokens
only — $ totals cover metered tiers.</p>
<script>
const DATA =
HTML_HEAD
printf '%s\n' "$SUMMARY" >> "$OUT"
cat >> "$OUT" <<'HTML_TAIL'
;
const esc = s => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const ktok = n => n == null ? '?' : n >= 1000 ? (n/1000).toFixed(1).replace(/\.0$/,'') + 'k' : String(n);
const dur = ms => ms == null ? '?' : ms < 1000 ? ms + 'ms' : ms < 60000 ? (ms/1000).toFixed(1) + 's'
                 : Math.floor(ms/60000) + 'm' + Math.round(ms%60000/1000) + 's';
document.getElementById('rid').textContent = DATA.run_id;
const t = DATA.totals;
document.getElementById('totals').innerHTML = [
  ['tokens in→out', ktok(t.input_tokens) + ' → ' + ktok(t.output_tokens)],
  ['metered cost', '$' + (t.metered_cost_usd ?? 0).toFixed(4)],
  ['wall time', dur(DATA.wall_ms)],
  ['operations', String(t.events)],
  ['errors', String(t.errors)],
  ['tiers', Object.entries(t.by_tier || {}).map(([k,v]) => k + '×' + v).join('  ') || '—'],
].map(([k,v]) => '<div><span class="muted">' + esc(k) + '</span><b>' + esc(v) + '</b></div>').join('');
function nodeHtml(n) {
  if (['tracker_transition','gate','feature_toggle','missing_dependency'].includes(n.kind))
    return '<div class="mark">◆ ' + esc(n.label) + (n.summary ? ' — ' + esc(n.summary) : '') + '</div>';
  const badges =
    (n.tier ? '<span class="badge tier">' + esc(n.tier) + '</span>' : '') +
    (n.model ? '<span class="badge">' + esc(n.model) + '</span>' : '') +
    '<span class="badge">' + ktok(n.usage && n.usage.input_tokens) + '→' +
      ktok(n.usage && n.usage.output_tokens) + ' tok</span>' +
    (n.est_cost_usd ? '<span class="badge">$' + n.est_cost_usd.toFixed(4) + '</span>' : '') +
    '<span class="badge">' + dur(n.duration_ms) + '</span>' +
    '<span class="badge st-' + esc(n.status || 'none') + '">' + esc(n.status || '—') + '</span>';
  const kids = (n.children || []).map(nodeHtml).join('');
  const body = (n.summary ? '<div class="nsummary">' + esc(n.summary) + '</div>' : '') + kids;
  return '<details' + (n.heuristic ? ' class="heuristic"' : '') + ' open><summary>' +
         esc(n.label) + badges + '</summary>' + body + '</details>';
}
document.getElementById('tree').innerHTML = DATA.nodes.map(nodeHtml).join('');
</script>
HTML_TAIL

echo "report written: $OUT" >&2
