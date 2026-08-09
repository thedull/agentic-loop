---
name: project_diffsize_binary_zero_and_multijson_argjson_dataloss
description: spec 013's diff-size subcommand reports 0/0 for a binary-only diff (violates the null-vs-zero rule it exists to enforce); its findings-count extraction can drop the ENTIRE agent_stop event, not just the field, when last_assistant_message contains two adjacent full JSON objects each with an array `findings` key
metadata:
  type: project
---

`scripts/observe.sh` `diff-size` subcommand (spec 013) sums `git diff
--numstat` columns with `awk '{a+=$1; d+=$2}'`. Git prints `-\t-\tpath` for
binary files. Awk coerces non-numeric `-` to 0 in numeric context, so a
binary-only diff (confirmed live: a fresh 500-byte file added, `git diff
--numstat` prints only the `-  -  bin.dat` line) ends with `NR>0` true and
`a=0, d=0` — the script emits `{"lines_added":0,"lines_removed":0}`. This is
indistinguishable from "no diff exists" (acceptance 1: null) and directly
contradicts acceptance 3 / the spec's own stated Red Gate warning: "a capture
that substitutes 0 for null passes a naive presence check while destroying
the distinction the whole metric family rests on." None of the shipped
fixtures (700-702) exercise a binary file.

Separately, the findings-count extraction (`observe.sh` SubagentStop case)
pipes `.last_assistant_message` through `sed -e 's/^[^{]*//' -e
's/[^}]*$//'` then `jq -e '... else empty end'`, capturing stdout into
`$FINDINGS`. jq processes a stream of top-level JSON values by default. Fed
two adjacent well-formed JSON objects that BOTH have an array `findings` key
(e.g. a draft/scratch object before the real envelope), jq emits ONE LINE PER
OBJECT (confirmed live: input `{"note":"draft","findings":[3 items]}{"status":"ok","findings":[1 item]}`
produced `$FINDINGS` = `"3\n1"`). That multi-line string is then passed as
`--argjson findings "$FINDINGS"` to the OVERLAY-building jq call, which
raises `jq: invalid JSON text passed to --argjson` (confirmed, exit 2). The
OVERLAY assignment's exit status matches that failure, so `&& obs_event
agent_stop hook "$OVERLAY"` never runs — the hook still exits 0 (per its
"never break the session" contract) but **no event line is written at all**.
This is worse than a wrong `findings_count`: the whole `agent_stop` event
(duration, usage, tier, model, summary — everything) silently vanishes for
that subagent run. Not covered by any of cases 700-709.

**How to apply:** for any future spec around `git diff --numstat` parsing,
explicitly test a binary-file-only diff and check whether the null-vs-zero
contract is honestly preserved (binary changes are a real, non-empty diff
that cannot be counted in lines — treating it as 0 fabricates "no diff").
For any future spec parsing a subagent's `last_assistant_message` via a
sed/jq pipeline into `--argjson`, test a message containing two or more
adjacent syntactically-valid JSON objects that both match the extraction
filter — jq's default multi-document streaming can turn a single `$(...)`
capture into a multi-line string that poisons a downstream `--argjson` and
silently drops the entire enclosing event, not just the targeted field.
1st strike: spec 013 (comprehension-capture).
