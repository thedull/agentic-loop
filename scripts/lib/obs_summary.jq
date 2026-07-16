# obs_summary.jq — normalize one run's v1 events into a render-ready tree.
# Input: array of events (already filtered to a single run_id, slurped).
# Output: {run_id, started, ended, wall_ms, totals, nodes}.
#
# Hierarchy: agent nodes from paired agent_start/agent_stop; shim_call events
# attach to the agent whose [start,stop] interval contains their timestamp
# (time-overlap HEURISTIC at second granularity — flagged on the node as
# heuristic:true, rendered as a dashed edge). Unattached shims, headless
# iterations and marker events (tracker/gate/toggles) sit at the root.

def nz: if . == null then 0 else . end;

. as $ev
| ($ev | map(select(.event == "agent_start"))) as $starts
| ($ev | map(select(.event == "agent_stop")))  as $stops
| ($ev | map(select(.event == "shim_call")))   as $shims
| ($ev | map(select(.event == "headless_iteration"))) as $iters
| ($ev | map(select(.event | IN("tracker_transition","gate","feature_toggle",
                               "missing_dependency")))) as $marks

# --- agent nodes (paired) ---------------------------------------------------
| ($starts | map(. as $s
    | (($stops | map(select(.agent_id == $s.agent_id))) | first) as $p
    | {kind: "agent",
       id: $s.agent_id,
       ts: $s.ts,
       stop_ts: ($p.ts // null),
       label: ($s.agent_type // "agent"),
       tier: ($p.tier // $s.tier),
       model: ($p.model // null),
       usage: ($p.usage // $s.usage),
       est_cost_usd: ($p.est_cost_usd // null),
       duration_ms: ($p.duration_ms // null),
       status: (if $p == null then "running" else ($p.status // "ok") end),
       summary: ($p.summary // null),
       heuristic: false,
       children: []}))                                    as $agents0
# orphan stops (start event lost): still show them
| ($stops
   | map(select(.agent_id as $id | ($starts | map(.agent_id) | index($id)) | not))
   | map({kind: "agent", id: .agent_id, ts: .ts, stop_ts: .ts,
          label: (.agent_type // "agent"), tier, model, usage,
          est_cost_usd, duration_ms, status: (.status // "ok"),
          summary, heuristic: false, children: []}))      as $orphans

# --- shim nodes, attached by time overlap ------------------------------------
| ($shims | map(. as $c
    | (($agents0
        | map(select(.stop_ts != null and .ts <= $c.ts and $c.ts <= .stop_ts)))
       | first) as $host
    | {kind: "shim",
       id: null,
       host: ($host.id // null),
       ts: $c.ts,
       label: ($c.agent_type // "shim"),
       tier: $c.tier, model: $c.model, usage: $c.usage,
       est_cost_usd: $c.est_cost_usd, duration_ms: $c.duration_ms,
       status: $c.status, summary: $c.summary,
       heuristic: ($host != null),
       detail: $c.detail, children: []}))                 as $shimnodes

| ($agents0 + $orphans
   | map(. as $a | .children = ($shimnodes | map(select(.host == $a.id)))))
                                                          as $agents
| ($shimnodes | map(select(.host == null)))               as $rootshims

# --- headless iterations & marker events -------------------------------------
| ($iters | map(
    {kind: "headless_iteration", id: null, ts: .ts,
     label: ("iteration " + ((.detail.iteration // "?") | tostring)),
     tier: .tier, model: .model, usage: .usage,
     est_cost_usd: .est_cost_usd, duration_ms: .duration_ms,
     status: (if .detail.check_cmd_passed == true then "ok"
              else (.status // "ok") end),
     summary: (if .detail.check_cmd_passed == true
               then "check_cmd passed" else "check_cmd still failing" end),
     heuristic: false, children: []}))                    as $iternodes
| ($marks | map(
    {kind: .event, id: null, ts: .ts,
     label: (if .event == "tracker_transition"
             then ((.detail.spec_file // "spec") + ": "
                   + (.detail.from_status // "?") + " -> " + (.detail.to_status // "?"))
             elif .event == "gate" then ("usage gate: " + (.detail.verdict // "?"))
             elif .event == "feature_toggle"
             then ("toggle " + (.detail.feature // "?") + " (" + (.detail.decided_by // "?") + ")")
             else ("missing dependency: " + (.detail.feature // "?")) end),
     tier: null, model: null, usage: null, est_cost_usd: null,
     duration_ms: null, status: (.status // null),
     summary: (.detail.reason // null),
     heuristic: false, children: []}))                    as $marknodes

# --- totals -------------------------------------------------------------------
| ($stops + $shims + $iters) as $leaves
| {run_id: (($ev | first).run_id // "unknown"),
   started: (($ev | map(.ts) | min) // null),
   ended:   (($ev | map(.ts) | max) // null),
   wall_ms: (try ((($ev | map(.ts) | max | sub("\\.[0-9]+"; "") | fromdateiso8601)
                 - ($ev | map(.ts) | min | sub("\\.[0-9]+"; "") | fromdateiso8601)) * 1000)
             catch null),
   totals: {
     events: ($ev | length),
     input_tokens:  ($leaves | map(.usage.input_tokens | nz)  | add | nz),
     output_tokens: ($leaves | map(.usage.output_tokens | nz) | add | nz),
     metered_cost_usd: ($leaves | map(.est_cost_usd | nz) | add | nz),
     by_tier: ($leaves | map(.tier // "unknown") | group_by(.)
               | map({key: .[0], value: length}) | from_entries),
     errors: ($leaves | map(select(.status == "error" or .status == "blocked"))
              | length)
   },
   nodes: (($agents + $rootshims + $iternodes + $marknodes) | sort_by(.ts))}
