#!/usr/bin/env python3
"""MAINTAINER TOOL — plugin-repo only, never scaffolded into a project, never
run by the loop. The rest of this toolkit is deliberately bash+jq with zero
interpreter dependency because it runs unattended inside every project; this
script runs zero times unattended — only when a maintainer edits
templates/observability/dashboards.md and wants matching importable JSON.

Parses that markdown into OpenObserve dashboard JSON. The markdown stays
authoritative — this script derives panels from its headings/SQL, so doc and
dashboards can never silently drift apart. Regenerate after any edit to
dashboards.md:

    python3 scripts/observe_dashboards_gen.py \\
        templates/observability/dashboards.md \\
        templates/observability/dashboards

Schema (v8 panel/tab/dashboard shape) reverse-verified against a live
OpenObserve 0.91.5 instance: POST /api/{org}/dashboards, inspect the echoed
body; all 14 generated panels then confirmed to execute error-free and
return real rows against real pushed events (see docs/observability-architecture.md
§ dashboards for the record). Field-flattening convention
(usage.input_tokens -> usage_input_tokens, detail.to_status -> detail_to_status)
confirmed against the same instance after a real observe_push.sh run.

Committed as generated output: templates/observability/dashboards/*.json —
those files are what ships and what scripts/observe_dashboards_import.sh
reads; this script is how they were produced and how they get regenerated.
"""
import json, re, sys, pathlib

MD = pathlib.Path(sys.argv[1])
OUT_DIR = pathlib.Path(sys.argv[2])
STREAM = "agentic"

text = MD.read_text()

# Split into boards by "## Board N — Title"
board_re = re.compile(r"^## Board \d+ — (.+)$", re.M)
boards = []
matches = list(board_re.finditer(text))
for i, m in enumerate(matches):
    title = m.group(1).strip()
    start = m.end()
    end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
    boards.append((title, text[start:end]))

# Within a board: "**Panel title** — kind:\n```sql\n...\n```"
panel_re = re.compile(
    r"\*\*(?P<title>[^*]+)\*\*\s*—\s*(?P<kind>.+?):\s*\n```sql\n(?P<sql>.*?)\n```",
    re.S,
)

def norm_sql(sql: str) -> str:
    return " ".join(sql.split())

def panel_type(kind: str) -> str:
    k = kind.lower()
    if "single stat" in k:
        return "metric"
    if "table" in k:
        return "table"
    if "stacked bar" in k or ("bar" in k and "stack" not in k) or "bars" in k:
        return "bar"
    if "time series" in k or "line" in k:
        return "line"
    return "table"

def col_aliases(sql: str):
    """Ordered list of SELECT-clause aliases, in appearance order."""
    select_part = re.split(r"\bFROM\b", sql, maxsplit=1, flags=re.I)[0]
    select_part = re.sub(r"^\s*SELECT\s+", "", select_part, flags=re.I)
    # split on top-level commas (no nested parens in these queries beyond
    # function calls, which is exactly why a paren-depth counter is enough)
    parts, depth, cur = [], 0, ""
    for ch in select_part:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        parts.append(cur)
    aliases = []
    for p in parts:
        p = p.strip()
        m = re.search(r"\bAS\s+(\w+)\s*$", p, re.I)
        if m:
            aliases.append(m.group(1))
        else:
            # bare column reference, e.g. "phase" or "spec_id"
            aliases.append(p.split(".")[-1].strip())
    return aliases

def build_panel(idx, title, kind, sql):
    ptype = panel_type(kind)
    sql = norm_sql(sql)
    aliases = col_aliases(sql)
    has_group_by = re.search(r"\bGROUP BY\b", sql, re.I) is not None

    x, y, breakdown = [], [], []

    def field(a):
        return {"label": a, "alias": a, "column": a, "color": None}

    if ptype == "metric":
        # single stat(s): every alias is a value, no axes
        y = [field(a) for a in aliases]
    elif ptype == "table":
        # every alias is a display column; OpenObserve tables read x[] as
        # the ordered column list when no y[] is given a chart role
        x = [field(a) for a in aliases]
    else:  # bar / line
        remaining = list(aliases)
        # "t" (our histogram(ts) alias) is always the x-axis when present
        if "t" in remaining:
            x = [field("t")]
            remaining.remove("t")
        # a single non-numeric-looking, non-t leftover column with GROUP BY
        # is the breakdown dimension (phase, spec_id, spec) — heuristic:
        # anything that isn't clearly an aggregate result name.
        AGGREGATE_HINTS = {"p50", "p90", "err_pct", "postpones", "metered_usd",
                           "stochastic", "deterministic", "events", "tokens",
                           "llm_errors", "reopens"}
        if has_group_by:
            for a in list(remaining):
                if a not in AGGREGATE_HINTS and not x:
                    # no "t" present (Board 3 bar charts group by spec_id/spec
                    # directly) -> that grouping column IS the x-axis, not a
                    # breakdown, since there's no time dimension to breakdown
                    # against.
                    x = [field(a)]
                    remaining.remove(a)
                elif a not in AGGREGATE_HINTS:
                    breakdown = [field(a)]
                    remaining.remove(a)
        y = [field(a) for a in remaining]

    return {
        "id": f"panel{idx}",
        "type": ptype,
        "title": title,
        "description": "",
        "config": {"show_legends": True, "legends_position": None,
                   "base_map": None, "map_view": None},
        "queryType": "sql",
        "queries": [{
            "query": sql,
            "vrlFunctionQuery": None,
            "customQuery": True,
            "fields": {
                "stream": STREAM, "stream_type": "logs",
                "x": x, "y": y, "z": [], "breakdown": breakdown,
                "filter": {"filterType": "group", "logicalOperator": "AND",
                          "conditions": []},
            },
            "config": {"promql_legend": "", "layer_type": "scatter",
                      "weight_fixed": 1.0},
        }],
    }

OUT_DIR.mkdir(parents=True, exist_ok=True)
manifest = []
for title, body in boards:
    panels = []
    for i, pm in enumerate(panel_re.finditer(body), start=1):
        panels.append(build_panel(i, pm.group("title").strip(),
                                  pm.group("kind").strip(), pm.group("sql")))
    # A default window is not cosmetic. Events are indexed at the time the
    # work actually happened, so a factory that last ran yesterday falls
    # entirely outside OpenObserve's fallback range ("Past 15 Minutes") and
    # a correct board over correct data opens completely empty — which reads
    # as broken. Tonight is the evening-review board and wants today; the
    # trend boards want weeks. Still just a default the viewer can change.
    window = "1d" if title.startswith("Tonight") else "30d"
    dash = {
        "title": f"Agentic Loop — {title}",
        "dashboardId": "",
        "description": f"Generated from templates/observability/dashboards.md — board: {title}",
        "role": "",
        "owner": "",
        "tabs": [{"tabId": "default", "name": "default", "panels": panels}],
        "variables": {"list": []},
        "defaultDatetimeDuration": {"startTime": None, "endTime": None,
                                    "relativeTimePeriod": window,
                                    "type": "relative"},
    }
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    fname = OUT_DIR / f"{slug}.dashboard.json"
    fname.write_text(json.dumps(dash, indent=2) + "\n")
    manifest.append((title, len(panels), fname.name))
    print(f"{title}: {len(panels)} panel(s) -> {fname.name}")

print(f"\n{sum(m[1] for m in manifest)} panels across {len(manifest)} boards")
