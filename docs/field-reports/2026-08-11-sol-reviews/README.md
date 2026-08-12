# Field report — GPT-5.6 Sol as a cross-family adversary (2026-08-11)

**What this is:** the five raw worker envelopes from the first time this repo
pointed a real non-Claude model at its own code, preserved verbatim. They cost
**$2.22** and are **not reproducible** — the OpenRouter key has been revoked, and
the files they reviewed have since been fixed.

**Why they are committed:** §6 of [`../../hardening-2026-08.md`](../../hardening-2026-08.md)
makes claims about what these reviews found. This is the evidence for them. A
claim about model quality with no artifact behind it is an anecdote.

| file | target | model | findings | billed |
|---|---|---|---|---|
| `01-validate_envelope-plain-sol.json` | `scripts/lib/validate_envelope.jq` | `openai/gpt-5.6-sol` | 4 | $0.066 |
| `02-validate_envelope-sol-pro.json` | same file, same input | `openai/gpt-5.6-sol-pro` | 5 | $0.390 |
| `03-tracker-sol-pro.json` | `scripts/lib/tracker.sh` | `openai/gpt-5.6-sol-pro` | 7 | $0.600 |
| `04-observe-sol-pro.json` | `scripts/observe.sh` | `openai/gpt-5.6-sol-pro` | 3 | $0.447 |
| `05-common-sol-pro.json` | `scripts/lib/common.sh` | `openai/gpt-5.6-sol-pro` | 5 | $0.640 |

All runs: `--mode adversary --via openrouter --effort max`, blind (the model got
the file and its stated contract, never the reasoning that produced it).

---

## The headline result

**19 findings reported. 19 confirmed real.** Zero false positives across four
files.

Every one was reproduced in a sandbox or read directly in the source before
being acted on — the verification commands are in the git history of PRs #18,
#22, #23, #24 and #26.

What makes that number worth something is **what the code had already survived**:

- a suite that was green at 300+ tests
- repeated blind review by Claude subagents (`loop-reviewer`) during the specs
  that built these very files
- in three cases, code written *that same day* under Red Gate discipline and
  mutation testing

Three of the nineteen were **safety gates that had never once fired** —
`spec_check` fail-open, the hardened-review bypass, and `claim`'s unrestricted
transitions. Those are the findings that justify a cross-family adversary
specifically: they were invisible to us because the same reasoning that built the
gate also wrote its tests.

## Where it was wrong

Three of the nineteen were imprecise, and all three are worth knowing about
before trusting this class of output:

1. **Wrong mechanism, right smell** (`04-observe`, finding 3). Claimed a
   leading-zero start marker "can terminate the script nonzero". It does not —
   measured `rc=0`. The truth was worse: bash abandons the branch and jumps to
   `exit 0`, silently losing the telemetry event and orphaning the marker.
   *Writing the fix against the reported symptom would have tested the wrong
   thing.*
2. **Incomplete** (`04-observe`, finding 2). Reported that `findings_count` read
   the wrong JSON path. True — but it missed that the same extraction also broke
   on any pretty-printed envelope, which was the far more common failure.
   Verifying the reported half surfaced the unreported half.
3. **Real but unreachable** (`05-common`, finding 4). A rounded threshold
   comparison that can under-enforce. Correct as code analysis; not reachable
   with the committed price table, where the cheapest possible estimate sits an
   order of magnitude above the rounding boundary. Fixed anyway, recorded as what
   it is.

So: **19/19 pointed at something real, ~16/19 were precise about it.** Useful
calibration if you are deciding how much verification to budget — the answer is
"all of it, and it will still pay".

## Structured output held up

Spec 016 had just shipped a contract requiring every finding to carry a
`location` — either `{file, line_start, line_end}` or `null` paired with a
non-empty `searched` scope. This was its first contact with a real model.

**The model honoured it correctly on first use**, including the subtle part:
three findings carried full locations, and the fourth used the `null` + `searched`
form *appropriately*, for a finding about something missing rather than something
present. That is the distinction the contract exists to capture, and nothing in
the prompt spelled out which to choose.

The gate itself did not fire — the model wrote `.result.findings` and the
validator inspected `.findings` (see hardening §4.1). **The contract was right;
the plumbing was wrong.** Worth separating, because it is easy to read that
failure as a model failure and it was not.

## Pro versus plain, on identical input

`01` and `02` review the **same file at the same commit** — the pre-hardening
validator, pinned out of git so the only variable was the model.

| | plain Sol | Sol Pro |
|---|---|---|
| findings | 4 | 5 |
| input tokens | 2,231 | 18,759 |
| output tokens | 2,174 | 10,447 |
| billed | $0.066 | $0.390 |

Both found the same two high-severity defects. Pro found one additional
low-severity one (an unenforced summary word limit) and **calibrated severity
better** — it ranked the `false`-coercion defect *high* where plain Sol said
*medium*, and Pro was right, because `"findings": false` disables every finding
rule at once.

**This is one sample per model and should not carry more weight than that.**
It is consistent with "Pro is somewhat better" and equally consistent with "both
are comfortably above this task's difficulty". A file that separated them
sharply would be better evidence; this one did not.

The economics are the clearer half: **identical list price** ($5/$30 per 1M,
verified in the catalog the same day), so Pro costs more per *call* purely by
spending more reasoning tokens — 8.4× the input, 4.8× the output here.

## What to re-verify before trusting any of this

- Prices and context lengths (a catalog entry moved 34% in one day during this
  work)
- That `openai/gpt-5.6-sol-pro` still exists under that id
- That Pro and plain still share a list price — the comparison's whole economic
  argument rests on it
