# Worker envelope validator.
# Usage: jq -e -f validate_envelope.jq < envelope.json
# Exits 0 if the envelope is valid, non-zero otherwise.

def fail(msg): error("envelope invalid: " + msg);
def ffail($i; msg): fail("finding " + ($i | tostring) + ": " + msg);

# Every finding must say WHERE. Either a machine-checkable location, or an
# explicit statement of the scope that was examined and came up empty. Prompt
# text asking for evidence is a request a model can decline; this is a refusal.
# Note the rule keys off the presence of `findings`, not off the worker name —
# an allowlist of worker names is defeated by renaming the worker.
def check_finding($i; $f):
  if ($f | type) != "object" then ffail($i; "must be an object") else . end
  # The documented finding shape is claim + evidence + severity + location. Only
  # location was ever enforced, so a finding carrying nothing but a location and
  # a searched scope passed — validating the citation while ignoring the claim
  # it was supposed to support.
  | (if (($f.claim | type) == "string") and ($f.claim | test("\\S"))
       then . else ffail($i; "claim must be a non-empty string") end)
  | (if (($f.evidence | type) == "string") and ($f.evidence | test("\\S"))
       then . else ffail($i; "evidence must be a non-empty string") end)
  | (if ($f.severity as $sv | ["high","medium","low"] | index($sv)) != null
       then . else ffail($i; "severity must be high|medium|low") end)
  | if ($f | has("location")) then . else
      ffail($i; "must carry a location object {file, line_start, line_end}, or location: null together with a non-empty searched scope")
    end
  | ($f.location) as $l
  | if $l == null then
      if (($f.searched // "") | type) != "string" then
        ffail($i; "searched must be a string when location is null")
      # A scope has to NAME something, so it must contain at least one letter or
      # digit. Testing \S instead lets zero-width characters through — U+200B,
      # U+FEFF, U+2060 and the rest of the Cf category are not \s to oniguruma,
      # so `searched: "​"` would read as a commitment while being blank on
      # screen. Requiring \p{L}/\p{N} also rejects punctuation-only ("...").
      elif (($f.searched // "") | test("[\\p{L}\\p{N}]") | not) then
        ffail($i; "location is null, so searched must name the scope that was examined (at least one letter or digit; whitespace, zero-width characters and punctuation alone do not name anything)")
      else . end
    elif ($l | type) != "object" then
      ffail($i; "location must be an object {file, line_start, line_end} or null, not a " + ($l | type))
    else
      # No separate has(file, line_start, line_end) check: a missing key reads as
      # null, and each per-key check below already refuses null. Mutation testing
      # showed the combined check was undetectable when deleted — subsumed, so it
      # was not a guard.
      (if (($l.file | type) == "string") and ($l.file | test("[\\p{L}\\p{N}]"))
           then . else ffail($i; "location.file must be a non-empty path (at least one letter or digit — same zero-width caveat as searched)") end)
      | (if (($l.line_start | type) == "number") and ($l.line_start == ($l.line_start | floor)) and ($l.line_start >= 1)
           then . else ffail($i; "location.line_start must be an integer >= 1") end)
      | (if (($l.line_end | type) == "number") and ($l.line_end == ($l.line_end | floor)) and ($l.line_end >= 1)
           then . else ffail($i; "location.line_end must be an integer >= 1") end)
      | (if $l.line_end >= $l.line_start
           then . else ffail($i; "location.line_end must be >= location.line_start") end)
    end
  # No numeric sibling may creep in beside the ordinal severity. LOOP_POLICY.md
  # forbids acting on self-reported confidence, and a 0-1 score is false
  # precision about a quantity the model cannot access. Rejecting ANY numeric
  # value at the top level of a finding beats a denylist of names, which is
  # defeated by calling it `weight`.
  | ([$f | to_entries[] | select((.value | type) == "number") | .key]) as $nums
  | if ($nums | length) > 0 then
      ffail($i; "numeric field(s) " + ($nums | join(", ")) +
                " are not allowed on a finding — severity is ordinal by policy (a numeric confidence or score is false precision)")
    else . end;

. as $e
| if ($e | type) != "object" then fail("top level must be an object") else . end
| if (($e.worker | type) != "string") or (($e.worker | length) == 0)
    then fail("worker must be a non-empty string") else . end
| if ($e.status | type) != "string" then fail("status must be a string") else . end
| if ($e.status as $s | ["ok","partial","error","blocked","needs_escalation","needs_input"] | index($s)) == null
    then fail("status must be one of ok|partial|error|blocked|needs_escalation|needs_input") else . end
| if ($e.summary | type) != "string" then fail("summary must be a string") else . end
| if ($e | has("result")) | not then fail("result field is required (may be null on error)") else . end
| if ($e.artifacts != null) and (($e.artifacts | type) != "array") then fail("artifacts must be an array of paths") else . end
# "array of paths" was enforced only as far as "array". artifacts[] is read as
# filenames downstream (finalize_envelope writes them, the runner's
# artifact_exists check stats them), so a number in there is a defect that
# surfaces far from its cause.
| if (($e.artifacts // []) | map(select(type != "string")) | length) > 0
    then fail("artifacts must contain only strings (paths)") else . end
| if ((($e.key_decisions // []) + ($e.caveats // []) + ($e.assumptions // []))
       | map(select(type != "string")) | length) > 0
    then fail("key_decisions, caveats and assumptions must contain only strings") else . end
| if ($e.key_decisions != null) and (($e.key_decisions | type) != "array") then fail("key_decisions must be an array") else . end
| if ($e.caveats != null) and (($e.caveats | type) != "array") then fail("caveats must be an array") else . end
| if ($e.assumptions != null) and (($e.assumptions | type) != "array") then fail("assumptions must be an array") else . end
| if ($e.confidence_ordinal != null)
     and ((["high","medium","low"] | index($e.confidence_ordinal)) == null)
    then fail("confidence_ordinal must be high|medium|low") else . end
| if ($e.usage != null) and (($e.usage | type) != "object") then fail("usage must be an object") else . end
| if ($e.findings != null) and (($e.findings | type) != "array") then fail("findings must be an array") else . end
| if (($e.result | type) == "object") and ($e.result.findings != null)
     and (($e.result.findings | type) != "array")
    then fail("result.findings must be an array") else . end
# Findings are validated WHEREVER THEY LIVE. The first live adversary call put
# them under `result` — reasonably, since envelope_instructions says result holds
# the content named by the output spec, and that spec said "findings" — and every
# rule here silently did not apply. A gate that inspects one location while the
# producer writes to another is not a gate; it is a coincidence that held until
# the first real response.
| (($e.findings // []) + (if ($e.result | type) == "object" then ($e.result.findings // []) else [] end)) as $all_findings
# Absent or empty findings is the shape every non-adversary worker emits, and it
# stays untouched: the comprehension below iterates zero times.
| ([ $all_findings | to_entries[] | check_finding(.key + 1; .value) ] | length) as $_checked
| $e
