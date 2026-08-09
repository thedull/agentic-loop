# obs_metrics.jq — the derive plane: rollups over v1 observability events.
# Input: slurped array of events (all runs, already date-filtered by the
# caller). Driven by observe_metrics.sh; see docs/observability-architecture.md
# §3 for the metric catalog this implements.
#
# Args (all provided by observe_metrics.sh):
#   $mode     "cost" | "phase" | "spec" | "estimate" | "mix"
#   $specmeta {path: {id, title, profile, effort_budget, bytes}} — spec-file
#             facts jq cannot read itself; joined into spec/estimate output
#   $budget   effort_budget filter for estimate mode ("" = every bucket)
#
# Principles carried over from obs_summary.jq: leaf events (shim_call,
# agent_stop, headless_iteration) are the only token/cost bearers — summing
# anything else double-counts. Metered $ and subscription tokens are never
# blended: est_cost_usd == null MEANS subscription, and stays out of $ sums.

def nz: if . == null then 0 else . end;

def leaves: map(select(.event | IN("shim_call","agent_stop","headless_iteration")));

# LLM-layer error: a worker call that failed or came back empty/partial.
# Deliberately NOT spec-level `blocked` — that is factory health, not an
# LLM reliability signal (see architecture doc §3B).
def is_llm_err: (.status == "error" or .status == "partial");

# pct(p) over an already-null-free numeric array. Nearest-rank on the sorted
# list; null when empty — never a fabricated 0.
def pct(p): sort | if length == 0 then null
  else .[((length - 1) * p / 100 | floor)] end;

def iso_ms: try (sub("\\.[0-9]+"; "") | fromdateiso8601 * 1000) catch null;

def token_sums:
  {input_tokens:  (map(.usage.input_tokens  | nz) | add | nz),
   output_tokens: (map(.usage.output_tokens | nz) | add | nz)};

# --- cost: the two honest numbers, plus the per-tier split -------------------
def cost:
  leaves as $l
  | ($l | map(select(.est_cost_usd != null))) as $metered
  | ($l | map(select(.est_cost_usd == null))) as $sub
  | {metered_usd: ($metered | map(.est_cost_usd) | add | nz),
     metered: ($metered | token_sums + {calls: length}),
     subscription: ($sub | token_sums + {calls: length}),
     by_tier: ($l | group_by(.tier // "unknown")
       | map({key: (.[0].tier // "unknown"),
              value: (token_sums
                      + {calls: length,
                         metered_usd: (map(.est_cost_usd | nz) | add | nz)})})
       | from_entries)};

# --- phase: spend + reliability per stage ------------------------------------
def phase_rollup:
  leaves
  | group_by(.phase // "unattributed")
  | map({key: (.[0].phase // "unattributed"),
         value: (token_sums
                 + {events: length,
                    metered_usd: (map(.est_cost_usd | nz) | add | nz),
                    llm_errors: (map(select(is_llm_err)) | length),
                    p50_duration_ms: (map(.duration_ms | select(. != null)) | pct(50)),
                    p90_duration_ms: (map(.duration_ms | select(. != null)) | pct(90))})})
  | from_entries;

# --- spec: the efficiency join ------------------------------------------------
# Work (leaf events by top-level spec_id) x lifecycle (tracker_transition by
# detail.spec_file — same string, that is the whole join) x spec-file facts
# ($specmeta). Cycle time comes in two segments, never blended:
#   machine  specd -> pr-open   (the factory's own performance)
#   merge    pr-open -> done    (human latency; needs reconcile-done/manual stamp)
def spec_rollup:
  . as $ev
  | ($ev | leaves | map(select(.spec_id != null)) | group_by(.spec_id)
     | map({key: .[0].spec_id,
            value: (token_sums
                    + {leaf_events: length,
                       metered_usd: (map(.est_cost_usd | nz) | add | nz),
                       llm_errors: (map(select(is_llm_err)) | length)})})
     | from_entries) as $work
  | ($ev | map(select(.event == "tracker_transition" and .detail.spec_file != null))
     | group_by(.detail.spec_file)
     | map(. as $t
       | ([$t[] | select(.detail.to_status == "specd")   | .ts] | min) as $specd
       | ([$t[] | select(.detail.to_status == "pr-open") | .ts] | min) as $propen
       | ([$t[] | select(.detail.to_status == "done")    | .ts] | max) as $done
       | {key: $t[0].detail.spec_file,
          value: {
            reopens: ([$t[] | select(.detail.to_status == "building")] | length
                      | if . > 0 then . - 1 else 0 end),
            blocked_count: ([$t[] | select(.detail.to_status == "blocked")] | length),
            cycle_machine_ms: (if $specd != null and $propen != null
              then (($propen | iso_ms) - ($specd | iso_ms)) else null end),
            cycle_merge_ms: (if $propen != null and $done != null
              then (($done | iso_ms) - ($propen | iso_ms)) else null end)}})
     | from_entries) as $lifecycle
  | (($work | keys) + ($lifecycle | keys) + ($specmeta | keys) | unique)
  | map(. as $id
      | {spec: $id}
        + ($specmeta[$id] // {})
        + ($work[$id] // {leaf_events: 0, input_tokens: 0, output_tokens: 0,
                          metered_usd: 0, llm_errors: 0})
        + ($lifecycle[$id] // {reopens: 0, blocked_count: 0,
                               cycle_machine_ms: null, cycle_merge_ms: null}));

# --- comprehension: PROXIES, not a measurement ---------------------------------
# Four numbers that correlate with comprehension debt. None of them measures it.
# Merge latency deliberately REUSES spec_rollup's cycle_merge_ms rather than
# recomputing the same segment a second, divergently.
#
# Build churn is `reopens` renamed for what it actually counts: transitions back
# into `building` BEFORE merge. It is not a post-merge signal and must never be
# rendered as one — `done` is terminal in the tracker, so no post-merge signal
# exists, and inventing one from a pre-merge counter is exactly the fabrication
# the honest-nulls rule forbids.
def comprehension:
  . as $all
  | (spec_rollup | map({key: .spec, value: .}) | from_entries) as $roll
  | ($all | map(select(.event == "diff_size" and .spec_id != null))
     | group_by(.spec_id)
     | map({key: .[0].spec_id, value: (sort_by(.ts) | last | .detail)})
     | from_entries) as $diffs
  | ($all | map(select(.event == "agent_stop" and .spec_id != null
                       and (.detail.findings_count != null)))
     | group_by(.spec_id)
     | map({key: .[0].spec_id, value: (sort_by(.ts) | last | .detail.findings_count)})
     | from_entries) as $finds
  | (($roll | keys) + ($diffs | keys) + ($finds | keys) | unique)
  | map(. as $id
      | ($diffs[$id].lines_added) as $a
      | ($diffs[$id].lines_removed) as $d
      | ($finds[$id]) as $f
      | (if $a == null or $d == null then null else ($a + $d) end) as $changed
      | {spec: $id,
         diff_added: $a,
         diff_removed: $d,
         findings: $f,
         findings_per_100_changed:
           (if $f == null or $changed == null or $changed == 0 then null
            else (($f / $changed) * 100) end),
         merge_latency_ms: ($roll[$id].cycle_merge_ms // null),
         build_churn: ($roll[$id].reopens // 0)});

# --- estimate: the lookup table the spec skill quotes -------------------------
# p25/p50/p75 of observed total tokens and metered $ per effort_budget bucket,
# with an explicit N and a hard insufficient-history guard. A lookup table,
# not a regression — see the small-N risk in the architecture doc.
def estimate:
  spec_rollup
  | map(select(.effort_budget != null and .leaf_events > 0))
  | group_by(.effort_budget)
  | map({effort_budget: .[0].effort_budget,
         n: length,
         sufficient: (length >= 5),
         tokens: (map(.input_tokens + .output_tokens)
                  | {p25: pct(25), p50: pct(50), p75: pct(75)}),
         metered_usd: (map(.metered_usd) | {p25: pct(25), p50: pct(50), p75: pct(75)})})
  | if $budget == "" then . else map(select(.effort_budget == $budget)) end;

# --- mix: deterministic machinery vs stochastic (LLM) activity ----------------
# Every guard shipped moves work from the stochastic column to the
# deterministic one; this trending deterministic is "gates, not
# documentation" showing up in telemetry.
def mix:
  map(select(.event | IN("run_start","run_end") | not)) as $ev
  | ($ev | map(select(.event
      | IN("shim_call","agent_start","agent_stop","headless_iteration")))) as $sto
  | ($ev | map(select(.event
      | IN("shim_call","agent_start","agent_stop","headless_iteration") | not))) as $det
  | ($ev | leaves) as $l
  | {events: {deterministic: ($det | length), stochastic: ($sto | length),
              stochastic_share: (if ($ev | length) == 0 then null
                else (($sto | length) / ($ev | length) * 100 | round) end)},
     first_attempt_ok: (if ($l | length) == 0 then null
       else {ok: ($l | map(select(.status == "ok" or .status == null)) | length),
             of: ($l | length)} end)};

if   $mode == "comprehension" then comprehension
elif $mode == "cost"     then cost
elif $mode == "phase"    then phase_rollup
elif $mode == "spec"     then spec_rollup
elif $mode == "estimate" then estimate
elif $mode == "mix"      then mix
else error("unknown mode: " + $mode) end
