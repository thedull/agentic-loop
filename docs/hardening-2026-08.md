# Hardening pass, 2026-08-10 → 2026-08-11

**What this covers:** seventeen merged PRs (#11–#27), the tail of the spec queue
and everything that came out of pointing a real cross-family adversary at this
repo's own code for the first time. **22 defects addressed**, three of them
safety gates that had never once fired. The suite went from **201 to 368 passing
tests**. Total metered spend: **$2.22**.

**Why this document exists:** the reasoning lives in seventeen commit messages
and four PR descriptions, which is not a readable form. This is the connected
version — what changed, what evidence forced it, and what it means for you when
you next run the loop.

---

## 0. How to read this

| If you want… | Read |
|---|---|
| The short version | §1, then §7 |
| What the loop finished building | §2 |
| Why the first live call broke twice | §3 |
| The defects an adversary found in our own code | §4 |
| **The most useful section** | §5 — the three recurring defect classes |
| Whether Sol — flat or Pro — is worth paying for | §6, then the raw envelopes in `docs/field-reports/2026-08-11-sol-reviews/` |
| What behaves differently now | §7 |
| What is deliberately still broken | §8 |
| The direct OpenAI transport, tested after the fact | §11 |

§5 is the one to read if you read only one. The individual defects are less
interesting than the fact that three of them were the *same mistake* in
different files.

---

## 1. What happened, in one table

| # | PR | Change | Driven by |
|---|---|---|---|
| 1 | [#11](https://github.com/thedull/agentic-loop/pull/11) | Spec 016 — a code location on every adversary finding | queue |
| 2 | [#12](https://github.com/thedull/agentic-loop/pull/12) | Spec 017 — Sol fundable through OpenRouter | queue |
| 3 | [#13](https://github.com/thedull/agentic-loop/pull/13) | Spec 018 — pre-flight cost gate | queue |
| 4 | [#14](https://github.com/thedull/agentic-loop/pull/14) | Spec 019 — alias refresh + delisted-id detection | queue |
| 5 | [#15](https://github.com/thedull/agentic-loop/pull/15) | Price `xiaomi/mimo-v2.5` | consequence of #13 |
| 6 | [#16](https://github.com/thedull/agentic-loop/pull/16) | Bound `max_tokens` on OpenRouter | **first live call** |
| 7 | [#17](https://github.com/thedull/agentic-loop/pull/17) | Budget `max_tokens` for hidden reasoning | **second live call** |
| 8 | [#18](https://github.com/thedull/agentic-loop/pull/18) | Four validator bypasses | **adversary review** |
| 9 | [#19](https://github.com/thedull/agentic-loop/pull/19) | Sol Pro as the frontier tier | your call |
| 10 | [#20](https://github.com/thedull/agentic-loop/pull/20) | Stop calling the estimate a ceiling | **live cost data** |
| 11 | [#21](https://github.com/thedull/agentic-loop/pull/21) | Findings get one home | **adversary review** |
| 12 | [#22](https://github.com/thedull/agentic-loop/pull/22) | Three tracker gates that never fired | **adversary review** |
| 13 | [#23](https://github.com/thedull/agentic-loop/pull/23) | observe.sh honours never-fatal | **adversary review** |
| 14 | [#24](https://github.com/thedull/agentic-loop/pull/24) | common.sh stops sourcing `.env` | **adversary review** |
| 15 | [#25](https://github.com/thedull/agentic-loop/pull/25) | `must_find` made trustworthy | our own traps |
| 16 | [#26](https://github.com/thedull/agentic-loop/pull/26) | Tracker enforces edges, not states | **adversary review** |
| 17 | [#27](https://github.com/thedull/agentic-loop/pull/27) | Summary limit warns, never refuses | **adversary review** |

Eleven of seventeen were driven by evidence that did not exist before we made a
real call. That ratio is the headline finding of the whole pass.

---

## 2. Part one — the spec queue finished

Four specs remained when the pass started. All four shipped through the normal
loop: Red Gate first, blind review, mutation testing.

### Spec 016 — a code location on every adversary finding

Turns *"cite your evidence"* from a prompt request a model can decline into a
refusal at receipt. Every finding must carry `location`: either
`{file, line_start, line_end}` or `null` **paired with a non-empty `searched`
scope** naming what was examined.

Absent is deliberately not the same state as null — an absent `location` is
refused even when `searched` is supplied, because "I forgot the field" and "I
looked and found nothing locatable" are different claims.

The validator is the gate; the `json_schema` on the request is an optimisation
only. Provider support for response formats varies, and *a gate that stops
gating when a parameter is dropped is not a gate.*

**Deliberately excluded:** any numeric `confidence`. `LOOP_POLICY.md:51-52`
forbids acting on self-reported confidence, and a 0–1 score is false precision
about a quantity the model cannot access. The validator refuses **any** numeric
field on a finding — a denylist of names is defeated by calling it `weight`.

### Spec 017 — Sol through OpenRouter

`--via openai|openrouter`, defaulting to today's behaviour. Same brief, same
prompts, same envelope; only the bill moves.

Two things that needed care:

- **Transport is never inferred from which keys are present.** A project that
  adds an OpenRouter key for bulk work must not silently start billing its Sol
  calls there. An absent key is a failure of the *requested* transport, not a
  reason to quietly use the other one.
- **The worker name could not simply be renamed.** `envelope_instructions()`
  interpolates the worker name into the system prompt, so calling it
  `sol/openrouter` would have changed the prompt and broken the
  byte-identical-prompts requirement silently. Prompts build as `sol`;
  `finalize_envelope` overrides `.worker` afterwards.

`sol/openrouter` still matches `obs_tier_from_worker`'s existing `sol*` glob, so
the expensive tier stays correctly attributed with **no change to `obs.sh` at
all**. Naming it `openrouter/…` like the bulk shim would have classified the most
expensive call in the system as bulk tier.

### Spec 018 — the pre-flight cost gate

*"The human confirms all metered spend"* existed in seven places as prose with
nothing enforcing it. This is the enforcement.

Every metered shim prints an estimate to **stderr** before issuing its request,
and refuses above a threshold with **exit 7** and a `status: "blocked"` envelope
unless explicitly authorised. `call_ollama.sh` spends nothing and is untouched.

Two rules that look like details and are not:

- **The estimate never reaches `usage.est_cost_usd`.** That field is reserved
  for what a provider actually reported. An estimate written there would be
  indistinguishable from a billed figure for the rest of the log's life.
- **A broken threshold refuses.** Empty, negative or non-numeric fails closed.
  A gate that reads garbage config and concludes "no limit" is worse than no
  gate, because it looks like one. `off` is the only disable; `0` keeps its
  literal meaning and refuses everything.

Authorisation is explicit only — `--authorize-cost` or
`FACTORY_COST_AUTHORIZED=1`. Never inferred from a TTY, because **the unattended
path is precisely the one nobody is watching.** One eval runs the refusal under
a pty to prove it.

### Spec 019 — alias refresh and delisted-id detection

Verified against the live catalog on 2026-08-10 (400 models):

| alias | was | context | now | context |
|---|---|---|---|---|
| `kimi` | `moonshotai/kimi-k2` | 131,072 | `moonshotai/kimi-k3` | 1,048,576 |
| `minimax` | `minimax/minimax-m2` | 204,800 | `minimax/minimax-m3` | 1,048,576 |
| `mimo` | `xiaomi/mimo-v2.5` | 1,050,000 | *unchanged* | 1,050,000 |

The bar is `context_length >= 1,000,000`, chosen during spec review because the
vaguer *"current generation"* was satisfiable by doing nothing — k2 and m2 are
**stale, not dead**, and both still resolve. Presence was never the bar.

`doctor.sh` gained its **first non-localhost dependency**, deliberately. A
delisted id is a well-formed string, so no offline test can catch it — the
`mimo` defect shipped silently into every stamped project. It mirrors the Ollama
gate: warn on unreachable, never fail the run, because offline is a normal state.

"Unverifiable" covers four states that are the same thing to a user: no network,
timeout, a response that isn't the catalog, and a catalog with **zero usable
models**. That last is *not* "all three aliases died at once" — the likeliest
cause is an upstream hiccup, and reporting three dead aliases would read as
catastrophic while being almost certainly wrong.

### The consequence nobody specced

018 refuses unpriced models. After 019, all three aliases resolved to ids with no
price entry, so **the whole bulk tier refused on any real call.** That was
acceptance 7 working exactly as written, and it took [#15](https://github.com/thedull/agentic-loop/pull/15)
to close — with a price verified against the live catalog, not inferred from the
`-pro` variant, which is a different model at a different price.

---

## 3. Part two — the first live calls, and the two defects no mock could catch

Everything above shipped with a green suite and **zero real provider calls.**
The first live call failed. So did the second. Neither failure was reachable by
any mocked test, and that is the point of this section.

### Failure 1 — the request was rejected before it ran

```
This request requires more credits, or fewer max_tokens.
You requested up to 65536 tokens, but can only afford 40000.
```

`call_sol.sh --via openrouter` and `call_openrouter.sh` sent **no `max_tokens`**.
The Responses API path doesn't need one; OpenRouter reserves credit against the
provider's default completion ceiling when the request doesn't bound it. So a
review that would have used ~2,000 tokens was rejected outright.

**Nothing was billed** — the request never ran.

The fix ([#16](https://github.com/thedull/agentic-loop/pull/16)) binds the cap to
the figure `preflight_gate` already assumed, which also gave `--effort` real
teeth instead of only changing a printed number.

### Failure 2 — the cap was spent entirely on thinking

Second attempt: **2,000 output tokens billed, empty message.**

Sol bills reasoning as output — [`call_sol.sh:5-6`](../scripts/call_sol.sh) has
said so since the beginning — and on the chat/completions transport it spends
that budget against `max_tokens` *before emitting a single visible character*.
The cap was consumed by reasoning, the envelope never started, and the call was
a total loss that still cost $0.074.

Setting `ASSUMED_OUT` to 2000/6000/18000 had treated those as *visible* output
budgets. They must cover reasoning too. Now 8000/16000/32000
([#17](https://github.com/thedull/agentic-loop/pull/17)).

**This is the same failure the cheapest tier already documents.**
[`templates/.env.example:44-48`](../templates/.env.example) warns that every
4B-class Ollama model measured *"spends its whole budget inside `<think>` and
returns an empty result the shim correctly reports as partial"*, and
[`doctor.sh:46`](../scripts/doctor.sh) gates on it. Identical failure class, top
of the ladder, roughly 1000× the price per wasted call — and it had been written
down for weeks at the bottom of the tier ladder while nobody thought to apply it
at the top.

### What the failures did right

Neither lied. The truncation warning fired, the non-JSON was wrapped as
`partial` with `confidence_ordinal: low` and an honest caveat, and the billed
figure came from OpenRouter's own `.usage.cost` rather than an estimate. The
degradation chain worked. A regression fixture built from that exact response
now pins the shape — capped, billed, empty.

---

## 4. Part three — what the adversary found in our own code

Four files, **19 findings reported and all 19 confirmed**, reviewed by
`openai/gpt-5.6-sol-pro` via OpenRouter (the validator review used plain Sol).
**Every finding was reproduced or read before being believed** — that discipline
mattered, as §4.5 shows, and it also turned up a twentieth defect the reviews
missed.

### 4.1 `validate_envelope.jq` — 4 defects ([#18](https://github.com/thedull/agentic-loop/pull/18))

Reviewed by pointing the adversary at the validator spec 016 had just shipped.

| severity | defect |
|---|---|
| high | findings nested under `result` bypassed **every** finding rule |
| high | a finding needed no `claim`, `evidence` or `severity` |
| medium | jq's `//` treats `false` as null, so `"findings": false` passed as `[]` |
| medium | "array of paths" was enforced only as far as "array" |

The first is the one that matters: **spec 016's gate did not fire on its own
first real use.** The model wrote `.result.findings`; the validator inspected
`.findings`. Every rule we had just built — location, searched, line sanity, the
numeric ban — silently did not apply to the first live adversary response we
ever received.

The consolation: the *contract* was right. Three findings carried full
`{file, line_start, line_end}`; one used `location: null` with a genuine
`searched` scope, correctly, for an absence-class finding. Only the plumbing was
wrong.

### 4.2 `tracker.sh` — 7 defects ([#22](https://github.com/thedull/agentic-loop/pull/22), [#26](https://github.com/thedull/agentic-loop/pull/26))

All seven high, all confirmed. Three defeated gates we had deliberately built:

- **`spec_check` was fail-open.** Only exit 2 refused. A checker that crashed or
  was killed reported "fine" by default, and a missing or non-executable checker
  was skipped **in silence**. Spec 014's gate, bypassed.
- **The hardened gate keyed on stdout of a call that prints nothing when it
  fails.** `tracker_profile` exits 6 with empty stdout, so the `== "hardened"`
  test was false and a hardened spec reached `pr-open` with **no security
  review**. Specs 001 and 005, bypassed.
- **`claim` took arbitrary from/to.** `claim queued specd` succeeded in a
  sandbox, skipping every `specd` gate. Now limited to the two edges any caller
  uses, which are precisely the gate-free ones.

Four were structural, fixed in [#26](https://github.com/thedull/agentic-loop/pull/26):

- **Any state could move to any other.** `advance <queued> done` and
  `advance <done> queued` both succeeded. The edges documented in the file's own
  header are now enforced.
- **The lock protected the write, not the decision.** The gated-status check ran
  against the status read *before* the lock and was never re-applied after, so a
  concurrent shelve was silently reversed.
- **Supersede citations verified against the wrong branch.** The base fell back
  to `symbolic-ref HEAD`, so on a feature branch a commit that never landed
  anywhere shared unblocked every dependent.
- **`claimed_by` is advisory** — documented rather than enforced; see §8.

### 4.3 `observe.sh` — 4 defects ([#21](https://github.com/thedull/agentic-loop/pull/21), [#23](https://github.com/thedull/agentic-loop/pull/23))

Against a file whose own line 30 reads *"deliberately no `-e`: nothing here may
kill the hook."*

- **A trailing flag hung it forever.** `shift 2` with one argument left shifts
  nothing and returns non-zero, so the loop never advanced. Measured: still
  running after 4 seconds. **In a hook, a hang is worse than a crash** — it
  blocks the session that invoked it.
- **A malformed marker cost the event.** See §4.5 — the review got this one
  wrong, and the truth was worse.
- **`findings_count` read the wrong path** — the systemic one, see §5.1.
- **The extraction broke on pretty-printed JSON** — found by verifying, not
  reported. See §4.5.

### 4.4 `common.sh` — 5 defects ([#24](https://github.com/thedull/agentic-loop/pull/24))

The library every shim sources, and the sharpest finding of the pass:

**`.env` was executed, not read.**

```
printf 'OPENROUTER_API_KEY=k\necho POLLUTED\n' > .env
→ POLLUTED lands on stdout AHEAD of the envelope
→ stdout is no longer valid JSON at all
```

stdout is supposed to carry exactly one envelope and nothing else, so any caller
piping to `jq` got garbage — and any command in that file ran with the shim's
privileges, from a file that ships with scaffolded projects.

Alongside it: `load_env`'s own comment claimed it does *"NOT export to children
beyond this process"* while `set -a` did exactly that, so every subagent, eval
sandbox and hook inherited the credentials. Both are now true statements about
the code rather than aspirations.

Also: a malformed brief produced **no envelope at all** (the jq destructuring
aborted under `set -e`), and a flag with no value aborted on an unbound variable.

### 4.5 Three times the review was wrong, and verifying caught it

This is why claims get reproduced before they get fixed.

**The reviewer said the octal marker "can terminate the script nonzero."** It
does not — verified `rc=0`. What actually happens is worse: bash abandons the
branch and jumps straight to `exit 0`, so the `agent_stop` event the hook exists
to record is **silently lost** and the marker file left orphaned. Silent
telemetry loss that reports success. Writing the case against the *reported*
symptom would have tested the wrong thing and shipped a green suite over a live
defect.

**The reviewer missed the bigger half of its own `findings_count` report.** It
flagged the `.findings` vs `.result.findings` path. Verifying turned up a second,
independent cause: the `sed` extraction runs **per line**, so a pretty-printed
envelope counted `null` while the byte-identical single-line one counted `1`.
Since `finalize_envelope` emits pretty JSON by default, that was the common case.

**One finding was real but unreachable.** `printf "%.4f"` before the threshold
comparison lets a figure below 0.00005 read as `0.0000`. True as code analysis —
and *not reachable* with the committed price table and the 2000-token
assumed-output floor, where the cheapest possible estimate is ~$0.00056. Fixed
anyway, but recorded as what it is rather than inflated into a live hole.

---

## 5. The three recurring patterns

**Read this section if you read nothing else.** The individual defects above are
less interesting than the fact that several were the *same mistake* in different
places.

### 5.1 One contract, three readers, three different assumptions

`.findings` versus `.result.findings` broke **three independent consumers in one
day**: the validator, `observe.sh`'s `findings_count`, and the comprehension
metric built on top of it.

The root cause was an ambiguity, not a bug. `envelope_instructions` says `result`
holds *"content per the OUTPUT SPEC"* — and every adversary brief sets
`output_spec: findings`. A model reading both is *entitled* to put findings under
`result`.

**Patching a third reader would have been treating the symptom.** The fix
normalises at `finalize_envelope`, the one boundary every shim worker passes
through, so downstream readers get one shape and never need to know the model
drifted. `observe.sh` also reads both, because a Task-tool subagent's message
never passes through `finalize_envelope` and so is never normalised.

**Lesson:** when the same defect appears in a third place, stop fixing readers.

### 5.2 Reading `$2` without checking it exists — three files, one evening

`tracker.sh`'s claim edges, `observe.sh`'s argument loops, `common.sh`'s brief
parser. Same habit, three places, each producing a bare crash or an infinite hang
instead of the structured envelope the contract promises.

Every one was found the same way: writing a case for a *trailing flag with no
value*, which nobody had thought to test anywhere.

**Lesson:** argument parsing is a contract surface. It deserves the same
adversarial input testing as anything that parses a file.

### 5.3 The test primitive was itself untrustworthy

`must_find` produced **three traps in one day**:

- **Case-insensitive matching.** `UNPRICED x` satisfies a needle of `priced x`,
  so a case asserting success passed on exactly the failure it existed to catch.
  This happened **twice** — the mimo price entry and the Sol Pro price entry —
  and both were caught only because the guards were mutation-tested afterwards.
- **Needles beginning with `-` could never match.** grep read them as options, so
  any assertion on a flag name was silently unusable.
- **`must_not_find` did not exist**, and its absence is what caused the other
  two: asserting a *failure* marker is absent is what those cases actually
  needed.

Fixed in [#25](https://github.com/thedull/agentic-loop/pull/25), and deliberately
done **before** the two large fix PRs that followed, because every case written
afterwards depends on it.

**Lesson:** a gate that needs mutation testing to be believed is backwards. Fix
the assertion primitive before writing more assertions on top of it.

### 5.4 A fourth pattern worth naming: cases that pass for the wrong reason

Seven times in this pass, a case passed before implementation for a reason
unrelated to the defect:

| case | why it passed hollowly |
|---|---|
| `--batch` refusal | `--batch` was an *unknown flag*, which also exits 2 |
| `--authorize-cost` | same — unknown flag, same exit code |
| determinism | compared two **empty** stderr streams |
| hardened profile | left the real `agents/` dir in place, so the profile resolved fine |
| supersede branch | SHA in the ACTOR position → refused with "needs a REF" |
| `must_not_find` | unknown check types are **skipped**, not failed |
| default threshold | asserted the word "threshold", never the value |

Each was caught by asking *"could this pass if the feature didn't exist?"* — and
each was strengthened before any code was written. That question is the whole of
the Red Gate discipline.

---

## 6. Cost, models, and what the numbers actually showed

**The raw envelopes for every review below are committed** at
[`docs/field-reports/2026-08-11-sol-reviews/`](field-reports/2026-08-11-sol-reviews/)
with a report of their own. They cost $2.22 and are not reproducible — the key
has been revoked and the files reviewed have since been fixed. A claim about
model quality with no artifact behind it is an anecdote.

### Did the cross-family adversary earn its place?

This is the question the whole tier ladder rests on, and this pass is the first
real evidence either way.

**19 findings reported across four files. 19 confirmed real. Zero false
positives.** Every one reproduced in a sandbox or read directly in the source
before being acted on.

What makes that worth something is what the code had already survived: a suite
green at 300+ tests, repeated blind review by Claude subagents during the specs
that built these very files, and in three cases code written *that same day*
under Red Gate discipline and mutation testing.

**Three of the nineteen were safety gates that had never once fired.** Those are
the findings that justify a *cross-family* adversary specifically, rather than
one more Claude reviewer: they were invisible to us because the same reasoning
that built each gate also wrote its tests.

It was not uniformly precise. Three findings were imprecise in ways worth knowing
(§4.5): one wrong mechanism with the right smell, one that missed the larger half
of its own report, one real-but-unreachable. So **19/19 pointed at something
real, roughly 16/19 were precise about it** — useful calibration if you are
deciding how much verification to budget. The answer is "all of it, and it still
pays".

**Structured output held up too.** Spec 016's location contract met a real model
for the first time here, and the model honoured it correctly on first use —
including using the `null` + `searched` form *appropriately*, for a finding about
something missing rather than something present. Nothing in the prompt spelled
out which to choose. The gate did not fire (§4.1), but that was our plumbing, not
the model: **the contract was right, the reader was looking in the wrong place.**

### Sol Pro versus plain Sol

Run on identical input — the pre-hardening validator, pinned out of git so the
only variable was the model.

| | plain Sol | Sol Pro |
|---|---|---|
| findings | 4 | **5** |
| input tokens | 2,231 | **18,759** |
| output tokens | 2,174 | 10,447 |
| **billed** | **$0.066** | **$0.390** |

**5.9× the cost for one additional low-severity finding.** Both found the same
two high-severity defects. Pro *did* rank the `false`-coercion defect high where
plain Sol said medium, and Pro was right — `"findings": false` disables every
finding rule at once.

Pro also **calibrated severity better**: it ranked the `false`-coercion defect
*high* where plain Sol said *medium*, and Pro was right — `"findings": false`
disables every finding rule at once.

**This is one sample per model and should not carry more weight than that.** It
is consistent with "Pro is somewhat better" and equally consistent with "both are
comfortably above this task's difficulty". A file that separated them sharply
would be better evidence; this one did not.

The economics are the clearer half. Pro is the default **on OpenRouter, which is
the only transport that carries it** (§11) — and it is the frontier tier at
— importantly — **the same list price** ($5/$30 per 1M, verified in the
catalog the same day). It costs more per *call* purely by spending more reasoning
tokens: 8.4× the input and 4.8× the output on this run, not a higher rate.
`OPENROUTER_MODEL_SOL` in `.env` reverts it with no code change.

### The estimate is not a ceiling, and live data proved it

I claimed in #16/#17 that capping `max_tokens` made the printed estimate an
upper bound on cost. **That was wrong**, and three consecutive runs disproved it:

| review | estimated | actual | over |
|---|---|---|---|
| Pro comparison | $0.4899 | $0.3899 | under |
| `tracker.sh` | $0.5344 | **$0.5998** | +12% |
| `common.sh` | $0.5088 | **$0.6396** | +26% |

`max_tokens` bounds **output**. Nothing bounds **input**, and a multi-pass model
re-bills context on every internal pass — 61,179 actual input tokens against
10,877 estimated on `tracker.sh`, a 5.6× inflation.

The gate is fine and still does its job: refusing on a forecast is legitimate.
What was wrong was the **assurance attached to the number**, in the one place
whose entire purpose is to be believed. The printed line now says
`input ESTIMATED … (not capped — a multi-pass model re-bills context and can
exceed this)` ([#20](https://github.com/thedull/agentic-loop/pull/20)).

### Where the money went

**$2.22 total.** The split is the useful part:

| spend | returned |
|---|---|
| $1.75 — four adversary reviews | **19 findings, all confirmed**, plus 1 more found while verifying them |
| $0.39 — Pro vs Sol comparison | 1 additional low-severity finding |
| $0.07 — one call whose cap went entirely to reasoning | nothing (see §3) |

Reviewing unreviewed code returned **11.4 defects per dollar**. Comparing two
models returned **2.6**. Worth remembering the next time the budget question
comes up.

**Counting honestly:** the four reviews reported 19 findings and every one was
confirmed. Verifying them turned up 1 further defect the reviews missed (§4.5),
and the live calls had already exposed 2 more (§3). **22 defects addressed in
total**, of which 3 were safety gates that had never once fired.

### One more incidental result

OpenRouter billed **$0.066349** where our own constants compute **$0.076375** —
we would have **overstated by 15%**. That is spec 017's "take the provider's
reported figure, never our table" decision earning its keep with real numbers
rather than an argument.

---

## 7. What behaves differently now

The operationally visible changes, in the order you are likely to hit them.

**`doctor.sh` now talks to the network.** It probes the OpenRouter catalog with a
5-second timeout to check the aliases are alive. Offline it emits one *"could not
verify"* warning and never fails the run. This is the change you will notice
first.

**Every metered call prints an estimate to stderr and can refuse.** Default
threshold **$1.00**. `--authorize-cost` or `FACTORY_COST_AUTHORIZED=1` to
proceed; `FACTORY_COST_THRESHOLD_USD=off` to disable refusals (the estimate still
prints). A broken threshold value **refuses** rather than disabling the gate.

**An unpriced model refuses with exit 7.** If you point `call_openrouter.sh` at a
model id not in `preflight_price()`, it will not run. Add the price, or authorise
explicitly. An unknown price is a reason to ask, not to bill blind.

**Sol runs the Pro variant** on both transports, overridable via
`OPENAI_MODEL_SOL` / `OPENROUTER_MODEL_SOL`.

**`--effort` now changes what a call can spend**, not just a printed number:
8000 / 16000 / 32000 token caps. Note `--effort ultra` estimates ~$0.97 against
the $1.00 default threshold, so a slightly larger prompt will trip the gate and
need `--authorize-cost`. That is the gate doing its job on the most expensive
path in the system.

**`.env` is parsed, not sourced.** Comments, blanks, `export` prefixes, quoted
values and CRLF all work. Arbitrary shell in that file no longer executes, and
credentials are no longer exported to child processes.

**The tracker enforces transitions.** `advance` refuses anything that isn't a
declared edge, and `claim` is limited to `specd→building` and `built→reviewing`.
`TRACKER_FORCE_LIVE=1` overrides both when you genuinely mean it.

**Adversary findings must carry a location.** A finding with neither a location
nor a `searched` scope is refused on receipt, and the shim exits 4.

**An overlong summary warns** (>100 words) but is never refused — see §8 for the
reasoning.

---

## 8. What is still open

Recorded deliberately, not forgotten.

**`claimed_by` is advisory.** The field looks like a lock and is not one:
`advance` takes no actor argument, so nothing compares a caller against it.
Survivable today because one loop runs at a time and the lock makes each write
atomic. **What is not protected is two concurrent loops**, where the loser's work
is silently overwritten rather than refused. Enforcing it means threading an
actor through every call site in `skills/build`, `skills/review` and
`templates/workflows`, plus a human override — a deliberate change, not a
side effect of a bug fix.

**`finalize_envelope` cannot enforce cost provenance.** Its cost argument is
arbitrary JSON with no marker distinguishing a provider-reported figure from an
estimate. True, and today the only callers are the shims themselves, which pass
provider figures. A design pass, not a patch.

**~~The direct OpenAI model id is unverified.~~ RESOLVED 2026-08-11 — and it was
wrong.** `gpt-5.6-sol-pro` **does not exist on the OpenAI API**. `GET /v1/models`
lists exactly `gpt-5.6-luna`, `gpt-5.6-sol` and `gpt-5.6-terra`; there is no
`-pro` variant at all. The direct transport now defaults to `gpt-5.6-sol`.

This changes a framing used elsewhere in this document: **the two transports do
not reach the same model.** `--via` selects a model tier as well as a bill, and
"same model, different pipe" is only true if you override one of them. Each side
now defaults to the best model it can actually reach. See §11.

**No eval exercises a genuine accept-but-never-respond hang.** The probe case
uses `127.0.0.1:9`, which fails via connection-refused in milliseconds. The
`--max-time` bound is asserted against the executed argv instead. Simulating a
real hang needs a background listener that is platform-dependent and flaky.

**The estimate has never been calibrated against an invoice.** The bytes/4
heuristic is labelled an estimate everywhere precisely because nobody has checked
it against a bill line by line.

**Prices are a 2026-08-07/10 snapshot.** They move — one model moved 34% in a
single day. Staleness is the accepted trade for determinism and no network call
in front of every request.

**The summary word limit warns rather than refuses.** This was a decision, not an
omission: it is the only stylistic rule in a validator that is otherwise all
structure and types, and refusing would discard a complete answer **already paid
for**. On a metered tier that is real money destroyed to enforce prose length.

---

## 9. Method notes

What actually caught what, since the answer is not "the tests".

**The Red Gate caught nothing on its own.** Every suite went red before
implementation, as required — but §5.4 lists seven cases that went *green* for
reasons unrelated to the feature. The gate works only in combination with the
question *"could this pass if the feature didn't exist?"*

**Mutation testing caught the most.** Every guard in every PR was deleted and the
suite re-run. It found:

- two genuinely dead guards (a subsumed key check in the validator, a duplicated
  edge check in the tracker), both removed — *a guard whose deletion nothing
  detects is not a guard*
- a **test seam that lied**: `doctor.sh`'s fetch log printed `--max-time` from a
  separate string while `curl` ran independently, so removing the bound left the
  case asserting it fully green. The logged line and the executed call are now
  one argv array.
- two real coverage gaps in the cost gate (nothing asserted the cost included
  output tokens; nothing sat exactly *on* the threshold)

**Live calls caught what no mock could.** Both #16 and #17 were invisible to a
green 300-test suite. The failure was in how a provider *reserves credit* and how
a reasoning model *spends a cap* — neither is expressible in a fixture.

**True-negative cases matter as much as positive ones.** Several fixes would have
"passed" by refusing everything: forcing the validator to reject all findings was
caught by 22 cases; a threshold of 0 warning on every call was caught by one.

---

## 10. Sources and evidence

- Live catalog: `https://openrouter.ai/api/v1/models`, fetched 2026-08-10, 400
  models. Context lengths and prices in §2 and §6 are from that response.
- Live adversary reviews: `openai/gpt-5.6-sol-pro` via OpenRouter (the first
  validator review used plain `openai/gpt-5.6-sol`), `--effort max`, 2026-08-10
  and 2026-08-11. **All five envelopes are committed verbatim** at
  [`docs/field-reports/2026-08-11-sol-reviews/`](field-reports/2026-08-11-sol-reviews/).
  The `validate_envelope.jq` one is additionally committed as
  `evals/fixtures/findings/live-sol-openrouter-review.json` and asserted still
  valid by a regression case, so hardening cannot quietly start rejecting real
  Sol output.
- Prices for `preflight_price()`: `docs/codex-subscription.md` §7.1 (snapshot
  2026-08-07) plus the live catalog for `xiaomi/mimo-v2.5`.
- Every `file:line` citation in this document was opened and confirmed rather
  than recalled.

**Volatile facts to re-verify before trusting them:** every price and context
length in §2 and §6, the `gpt-5.6-sol-pro` ids, and the claim that Pro and plain
Sol share a list price.

---

## 11. Addendum — the direct transport, tested (2026-08-11)

§8 listed the direct OpenAI model id as unverified. Testing it cost **$0.008**
and returned three findings, two of which were defects that made the default
path unusable.

### The default transport had never worked on this machine

```
./scripts/call_sol.sh: line 337: BETA_HEADER[@]: unbound variable
```

`call_sol.sh` expanded an **empty** `BETA_HEADER` array as `"${BETA_HEADER[@]}"`.
Under `set -u` on **bash 3.2** — which is what macOS ships and what this repo
runs on — that is an unbound variable, so the shim died *before* curl on every
non-`ultra` direct call. `ultra` was unaffected, because it populates the array.

**No mocked test could have caught it.** `MOCK_RESPONSE_FILE` short-circuits
above the curl block, so all 69 mocked `call_sol` cases skip that line entirely.
The safe idiom was already in this repo at `evals/run_eval.sh:91`; it had simply
never reached the shims.

Sweeping for the same shape found it a second time in **`call_fable.sh`**, where
`--no-fallback` leaves the array empty. **Two of the three metered shims were
dead on their default path**, both invisible for the same reason. The other three
candidate sites turned out to be properly guarded.

Both are fixed with `${BETA_HEADER[@]+"${BETA_HEADER[@]}"}`, and an
`SOL_API_ENDPOINT` / `FABLE_API_ENDPOINT` seam lets an eval drive the curl branch
against an unreachable local port — so the path that no test could reach now has
five.

### `gpt-5.6-sol-pro` does not exist on OpenAI

With the crash fixed, the call reached the API and answered the question it was
bought to answer:

```
OpenAI API error: The requested model 'gpt-5.6-sol-pro' does not exist.
```

`GET /v1/models` lists exactly **`gpt-5.6-luna`, `gpt-5.6-sol`, `gpt-5.6-terra`**.
No `-pro` variant. The id had shipped in #19 as a documented guess with an
override provided precisely because it was a guess — and the guess was wrong.

**The transports therefore reach different model tiers**, which is a real
correction to how #19 was described: `--via` changes the model as well as the
bill. Each side now defaults to the best model it can actually reach —
`gpt-5.6-sol` direct, `openai/gpt-5.6-sol-pro` on OpenRouter — and both remain
overridable.

### What the working call showed

`exit 0`, `status: ok`, `result: "ok"`, **$0.008 billed**.

- **The Responses API accepted our `text.format` json_schema** — `json_schema`,
  name `adversary_envelope`, requiring `claim`/`evidence`/`severity`/`location`.
  Spec 016's request-side optimisation is real on this transport, not just
  OpenRouter's.
- **bytes/4 was 13% under** on input (633 estimated, 725 actual) — consistent
  with the ~11% seen on OpenRouter, so the heuristic is stable across providers.
- **The estimate was 30× the actual cost** ($0.2432 vs $0.008), because the
  assumed-output term dominates any trivial call. That is the gate erring in the
  safe direction, but it means the printed number says little about a small call.

### Still not tested

`--effort ultra` — the one capability exclusive to this transport, and the one
code path in the system with **no `max_tokens` ceiling**. Case 002 proves it
reaches curl without crashing; nothing proves the beta header is transmitted or
that the account has multi-agent access. Testing it means an uncapped call, so
the honest prerequisite is bounding the direct transport first.
