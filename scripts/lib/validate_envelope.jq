# Worker envelope validator.
# Usage: jq -e -f validate_envelope.jq < envelope.json
# Exits 0 if the envelope is valid, non-zero otherwise.

def fail(msg): error("envelope invalid: " + msg);

. as $e
| if ($e | type) != "object" then fail("top level must be an object") else . end
| if (($e.worker | type) != "string") or (($e.worker | length) == 0)
    then fail("worker must be a non-empty string") else . end
| if ($e.status | type) != "string" then fail("status must be a string") else . end
| if ($e.status as $s | ["ok","partial","error","blocked","needs_escalation","needs_input"] | index($s)) == null
    then fail("status must be one of ok|partial|error|blocked|needs_escalation|needs_input") else . end
| if ($e.summary | type) != "string" then fail("summary must be a string") else . end
| if ($e | has("result")) | not then fail("result field is required (may be null on error)") else . end
| if (($e.artifacts // []) | type) != "array" then fail("artifacts must be an array of paths") else . end
| if (($e.key_decisions // []) | type) != "array" then fail("key_decisions must be an array") else . end
| if (($e.caveats // []) | type) != "array" then fail("caveats must be an array") else . end
| if (($e.assumptions // []) | type) != "array" then fail("assumptions must be an array") else . end
| if (($e.confidence_ordinal // "medium") as $c | ["high","medium","low"] | index($c)) == null
    then fail("confidence_ordinal must be high|medium|low") else . end
| if (($e.usage // {}) | type) != "object" then fail("usage must be an object") else . end
| if (($e.findings // []) | type) != "array" then fail("findings must be an array") else . end
| $e
