# Codex on a Subscription: Can GPT-5.6 Sol Be Our Adversary Without the Meter?

Sol is the top rung of our tier ladder and the only cross-family voice in the
system — *"best-of-best adversary/reviser — structural triggers only"*
(`templates/LOOP_POLICY.md:20`). It is also the only rung gated behind a human
confirmation on **every single call**, and the reason is money: `$5/$30` per 1M
tokens (`scripts/call_sol.sh:33-34`), with the shim's own header warning that
*"hidden reasoning tokens bill as output"* (`scripts/call_sol.sh:6`).

That cost is load-bearing. Seven places in this repo carry the same sentence —
never call metered tiers unattended, record `needs_escalation` instead
(`templates/LOOP_POLICY.md:198-201`, `skills/build/SKILL.md:93-95`,
`skills/review/SKILL.md:66-70`, `docs/factory.md:172-175` and `:210-211`,
`templates/workflows/factory.js:136`, `templates/RUNBOOK.md:105-106`), and
`skills/line/SKILL.md:35-40` declares it non-customizable so a project cannot
fork it away.

The question this document answers: **if a ~COP 100k/month ChatGPT subscription
funds Sol instead of an API key, does any of that change?**

The prompt was a [Valletta Software post](https://vallettasoftware.com/blog/post/run-gpt-5-6-in-claude-code)
describing a CLIProxyAPI setup. The owner has ruled that method out. The subject
here is the official **[`openai/codex-plugin-cc`](https://github.com/openai/codex-plugin-cc)**
plugin, examined at a pinned commit.

§1–§6 answer that question on its own terms. **§7 then reopens it**, because the
comparison those sections make — subscription versus API key — turns out to omit
a third option the owner already pays for. The short version, for anyone reading
only one section: `openai/gpt-5.6-sol` is on OpenRouter at the same list price
our shim already hardcodes, which makes scriptable Sol available today without
either credential under discussion.

**§8 answers a second question that arrived later**: whether a separate
OpenRouter account is worth opening as overflow capacity when Claude limits are
hit, and which model to reach for per task class. Its load-bearing finding is a
constraint rather than a price — such an account cannot back-fill the Claude Code
session itself, only work that gets delegated to a shim.

**Scope (owner-set): analysis only.** Nothing is installed, no policy is edited,
no code changes. §6 is a ranked backlog and everything in it is unbuilt.

Three ground rules, inherited from `docs/osmani-audit.md`:

- **Every claim about our system carries a `file:line`**, opened and confirmed
  rather than recalled.
- **Every claim about the plugin is cited to its own source at a pinned commit**,
  read via `gh api` rather than through a summarizer. It is an actively developed
  repository and every fact in §2 has a shelf life.
- **Third-party quota numbers are attributed as third-party.** OpenAI's own help
  pages refuse programmatic fetches (HTTP 403), so the figures in §3.3 come from
  independent trackers and are labelled as estimates, not facts. This is the
  honest-nulls rule (`scripts/lib/obs.sh:18-19`) applied to research.

---

# §1 — The proxy method, and why it is closed

The owner closed this before the analysis started, so this section is short. The
*reasons* are worth recording because two of them generalize.

**It inverts our own health check.** The method's step 3 writes
`ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` into `~/.claude/settings.json`.
`scripts/doctor.sh:23-25` already fails a project outright for the adjacent
case — an `ANTHROPIC_API_KEY` in `./.env` — because it flips the interactive
session off subscription billing. The proxy does the same class of thing one
level up.

**The article argues against itself on terms of service.** It states plainly
that routing a Claude subscription OAuth token through a third-party proxy
violates Anthropic's Consumer Terms, that consumer OAuth tokens have been
blocked outside Claude Code and Claude.ai since early 2026, and that the proxy
holds both vendors' credentials in a single place. (Paraphrased with
attribution rather than quoted — the article was read through a summarizing
fetch and verbatim wording could not be confirmed.)

**The structural objection is ours, not theirs, and it is the decisive one.**
The method makes Claude Code *be* Sol. Cross-family independence is the entire
purchase: an adversary drawn from the author's own model family is the
worker-grades-its-own-homework failure that the blind-review protocol exists to
prevent (`templates/LOOP_POLICY.md:69-74`). A proxy that swaps the orchestrator's
model deletes the property it claims to deliver. Even if the ToS problem
vanished tomorrow, this objection would stand.

---

# §2 — What the plugin actually is

Pinned at commit **`db52e28f4d9ded852ab3942cea316258ae4ef346`** (2026-07-08),
plugin version **1.0.6**. Every row below was read from that tree.

Paths below are relative to the plugin repository root; the plugin itself lives
under `plugins/codex/`.

| Property | Finding | Source |
|---|---|---|
| Transport | Codex **app-server** (JSON-RPC through a broker daemon), **not** `codex exec` | `plugins/codex/scripts/app-server-broker.mjs`, `.../lib/app-server.mjs`, probe at `.../lib/codex.mjs:892` |
| Auth | ChatGPT subscription (incl. Free) **or** OpenAI API key; *"`codex login` supports both ChatGPT and API key sign-in"* | `README.md:18`, `README.md:300` |
| Codex home | `$CODEX_HOME`, defaulting to `~/.codex` | `plugins/codex/scripts/lib/codex.mjs:654` |
| Runtime dep | the global `codex` binary, plus Node.js 18.18+ | `README.md:20` |
| Sandbox default | `sandbox: "read-only"`, `approvalPolicy: "never"` | `plugins/codex/scripts/lib/codex.mjs:67-68` |
| Review sandbox | hard-coded `"read-only"` | `plugins/codex/scripts/codex-companion.mjs:414` |
| Rescue sandbox | `request.write ? "workspace-write" : "read-only"` | `plugins/codex/scripts/codex-companion.mjs:491` |
| Autonomy | review commands carry `disable-model-invocation: true` — Claude **cannot** fire them | `plugins/codex/commands/adversarial-review.md` frontmatter |
| Surface | 8 slash commands, 1 subagent (`codex:codex-rescue`), 3 skills, hooks on SessionStart/SessionEnd/Stop | repo tree at the pinned SHA |
| Scriptable | **No.** Slash commands only. Nothing a `call_*.sh` shim can invoke | — |
| Output | structured JSON; verdict `approve` \| `needs-attention` | `plugins/codex/schemas/review-output.schema.json` |

## 2.1 Two corrections to a first reading

Both were wrong on my first pass and the corrections matter more than the
original guesses.

**Blindness holds.** I flagged the `SessionStart` hook — which supplies the
current transcript path — as a probable breach of the blind-review protocol. It
is not. `/codex:adversarial-review` reviews a **git diff**: working-tree, branch,
or `--base <ref>`, per its own `argument-hint`. Its review-target selection is
shared with `/codex:review` and it never receives Claude's conversation. The
transcript path feeds `/codex:transfer`, the session-import path, which is a
different command doing a different job.

**Attended-only is enforced upstream, not by us.** `disable-model-invocation: true`
means Claude Code cannot invoke the review commands on its own initiative — the
human types them. That is a *mechanical* guarantee of the property our seven
policy statements pursue with prose. It is worth noting plainly that upstream's
default is stronger here than our own enforcement, and equally worth noting that
it is upstream's to change.

## 2.2 The finding schema is stricter than ours

Worth its own subsection because it is a mechanism we could steal regardless of
whether the plugin is ever adopted.

Our adversary emits `findings: [{claim, evidence, severity}]`
(`scripts/call_sol.sh:66-67`), where `evidence` is free text. The plugin's schema
**requires** every finding to carry `file`, `line_start`, `line_end`, plus
`severity` (`critical|high|medium|low`), `title`, `body`, `recommendation`, and
`confidence`. A finding that cannot name a code location cannot be emitted at
all.

That is a structural anti-hallucination gate of exactly the shape this repo
prefers — a refusal rather than an instruction. Our own equivalent is a *prompt
line* asking for evidence before verdict (`scripts/call_sol.sh:61-62`), which is
a suggestion a model can decline.

One part of their schema we should **not** copy: `confidence` as a number in
`[0,1]`. Our policy distrusts exactly this — escalation fires *"NEVER on a
worker's self-reported confidence (self-reported confidence is unreliable by
construction)"* (`templates/LOOP_POLICY.md:51-52`) — and we deliberately use
`confidence_ordinal` (`high|medium|low`) instead. A model reporting `0.82`
communicates false precision about a quantity it has no access to.

---

# §3 — Three findings

## 3.1 (a) Their adversary answers a different question than ours

This is the finding that decides §4, and it is easy to miss because both things
are called "adversarial review."

**Ours asks: does this meet the spec?** The system prompt scopes hard —
*"Report ONLY correctness and requirement gaps. Do not report style, taste, or
hypothetical improvements — chasing those causes over-engineering"*
(`scripts/call_sol.sh:59-60`). The payload is the task spec plus the candidate
artifact, with the orchestrator's reasoning deliberately withheld
(`templates/LOOP_POLICY.md:71-73`).

**Theirs asks: how can this break?** `plugins/codex/prompts/adversarial-review.md`
opens with
*"Your job is to break confidence in the change, not to validate it"* and directs
attention at an enumerated attack surface: auth and trust boundaries, data loss
and irreversible state, rollback and idempotency, races and ordering, empty-state
and timeout behavior, version skew and migration hazards, observability gaps.

The payload difference is the crux: **their review contains no spec.** It is
handed a diff and the repository. It therefore *cannot* report a requirement gap,
because it is never told the requirement. Conversely ours cannot report a race
condition it has no repository access to observe.

These are complementary, not substitutable — and the complement lands precisely
on a gap we have already documented. `docs/osmani-audit.md` §2.4.3 records that
our entire security posture for shipped code is one bullet in the blind review
(`skills/review/SKILL.md:47`), and that the missing depth is what `profile:
hardened` should route to. The plugin's attack-surface list is close to a
ready-made version of that payload.

So the honest verdict is not "a cheaper Sol." It is: **a different reviewer that
happens to fill a hole we already named.**

## 3.2 (b) A subscription-funded Sol is unmetered, and our rule is written in dollars

Read the policy literally: *"No metered tiers unattended... The human confirms
ALL metered calls — no exceptions for autonomy"* (`templates/LOOP_POLICY.md:198-201`).
`skills/build/SKILL.md:95` closes with *"The human confirms all metered spend."*

A subscription-funded Sol is not metered. The rule stops applying **by its own
wording** while every reason behind it — bounded consumption, a human circuit
breaker on the most expensive rung — holds exactly as before.

The observability plane then goes quiet, and it goes quiet *correctly*, which is
what makes this dangerous. `scripts/lib/obs.sh:18-19` states the rule: *"est_cost_usd
stays null for subscription tiers: they are shared capacity, not dollars."* A
subscription Sol emitting `null` cost is behaving exactly as designed — and Sol's
only back-pressure signal disappears with it.

**Nothing else covers the gap.** Verified rather than assumed:

- `scripts/lib/usage_gate.sh` reads only `.agentic/usage.json`, mirrored from the
  **Anthropic** statusline payload's `rate_limits`. Its own header names the
  source: *"the only authoritative programmatic %-of-cap source Anthropic
  exposes."* It knows nothing about a ChatGPT quota.
- It also fails **open** in all three degraded cases — file missing (`:41`), no
  `mirrored_at` (`:49`), stale beyond threshold (`:54`) — deliberately, so a
  broken statusline cannot deadlock the factory.
- A grep across `scripts/`, `templates/` and `skills/` finds no mechanism of any
  kind that reads an OpenAI or ChatGPT quota. There is no second gate to lean on.

**Today the hole is closed by accident.** The only thing preventing an unattended
subscription-funded Sol call is that the plugin refuses model invocation (§2.1) —
upstream's design choice, in a file we do not own, reversible in a release we do
not control. Relying on it is not a safety property; it is a coincidence that
currently points our way.

The conclusion is a policy debt with a trigger, not an action item for today:
**if a scripted subscription transport is ever added, the rule must be
re-grounded on quota before the transport ships, not after.** §5 and §6 both
depend on this ordering.

## 3.3 (c) Plus is the binding constraint, and our payload is the one in the bug report

~COP 100k/month is ChatGPT Plus.

Independent trackers estimate the Plus allowance at roughly **15–90 GPT-5.6 Sol
messages per 5-hour window**, with a separate weekly cap, and report that the
5-hour cap was temporarily lifted for Plus/Pro/Business on 2026-07-12 with the
weekly limit still in force. These are third-party estimates. OpenAI's own rate
card and plan pages return HTTP 403 to programmatic fetches, so **none of these
numbers are confirmed at the source** and they should be treated as an order of
magnitude, not a budget.

What *is* confirmed is the shape of the complaint.
[`openai/codex#32606`](https://github.com/openai/codex/issues/32606) — *"GPT-5.6
Terra and Sol exhaust the 5-hour Codex usage limit within minutes"* — is open. A
Plus user reports Terra consuming almost the entire 5-hour window in a few
minutes on a repository audit, Sol behaving similarly, and roughly €40 of
additional purchased credits exhausted the same day. Their workaround was
rolling back to GPT-5.4 xhigh. No maintainer response is recorded on the issue.

**Our payload is the shape being complained about.** `build_task_prompt` inlines
the full contents of every `--input-path` into the request
(`scripts/lib/common.sh:147-157`). A Sol call in this factory is not a question;
it is a question plus every file the brief names. The plugin's diff-scoped review
is materially cheaper per call than our own Sol invocation would be on the same
change — which cuts *in favor* of the plugin and *against* any future scripted
transport reusing `build_task_prompt` unchanged.

**One configuration must stay off.** The optional Stop review gate fires on every
Claude response. Upstream's own warning: *"The review gate can create a
long-running Claude/Codex loop and may drain usage limits quickly. Only enable it
when you plan to actively monitor the session"* (`README.md:237`). On a Plus allowance that is a
quota bonfire. It is disabled by default; it should stay that way, and §6 item 7
makes that a check rather than a note.

---

# §4 — Can it be Sol? Split by role

A single verdict would be dishonest — the answer differs sharply by role.

| Role | Verdict | Why |
|---|---|---|
| **Attended adversarial review** | **Yes, and it is additive** | Read-only, human-invoked, diff-scoped; asks a question ours cannot (§3.1) |
| **Unattended review inside the factory loop** | **No** | Not scriptable at all. `evals/judge.sh:56` and every stage reach `call_sol.sh`; there is no entry point |
| **Implementer / delegated builder** | **Attended only, and it inverts the ladder** | `/codex:rescue` writes (`plugins/codex/scripts/codex-companion.mjs:491`). A non-Claude agent in the tree means the blind reviewer must become a Claude model — a role inversion touching `LOOP_POLICY`, `skills/build`, and the plugin-owned region at `templates/workflows/factory.js:136` |
| **Replacement for `call_sol.sh`** | **No** | Different transport, different payload, different output schema, no shim entry point |

Three consequences worth stating flatly:

**Adopting the plugin does not retire `OPENAI_API_KEY`.** The scripted Sol path
stays metered and stays gated. `doctor.sh:76-77` keeps reporting the key, and
`evals/judge.sh --tier sol` keeps costing money. This is a *second* Sol surface,
not a migration. Anyone reading §6 as a cost-saving plan has misread it.

**The implementer role is the expensive question, not the cheap one.** It is not
"can Codex write code" — obviously it can. It is that our build stage's entire
safety argument is Red Gate plus a blind reviewer from a different family. Put
Sol in the builder's seat and the reviewer must swap families to preserve the
property, which means the ladder is not extended but re-ordered. That is a
design change, not a configuration change, and nothing in this document
recommends it.

**The subscription buys attended capability, not autonomy.** Everything the
plugin unlocks requires a human at the keyboard, by upstream's own construction.
If the goal is more unattended Sol, this purchase does not deliver it — and §3.2
explains why the version that *would* deliver it is blocked on a policy decision
rather than on money.

---

# §5 — The scripted alternative, recorded not recommended

The plugin does not use `codex exec`, but it exists, and the option should be on
record rather than rediscovered later.

`codex exec` is the CLI's headless mode: prompt positional or via `-`, `--model`
to select the model, `--json` for a JSONL event stream in which `TurnCompleted`
carries token counts, and `--output-schema` / `--output-last-message` for
structured results.

That last pair is genuinely attractive here. Our shim currently coaxes JSON out
of free text with `extract_json_object` (`scripts/lib/common.sh:186-199`), a
best-effort parse that strips fences and then falls back to slicing between the
first `{` and last `}`. `--output-schema` would let us hand Codex
`scripts/lib/validate_envelope.jq`'s shape directly and delete the guessing.
Only lines 92–138 of `scripts/call_sol.sh` are provider-specific; everything
above them is transport-agnostic already.

It is nevertheless **not** recommended in this pass, for three reasons in
descending order of seriousness:

1. **It is blocked on §3.2.** A scripted subscription Sol is precisely the thing
   that opens the unmetered-autonomy hole. The rule gets re-grounded on quota
   first, or the transport does not ship.
2. **`codex exec` is an agent, not a completion.** It runs in a working
   directory with a sandbox. Our adversary contract is task-plus-candidate and
   nothing else; a reviewer that can read the repository can read the spec, the
   git log and `LEARNINGS.md`, and the blind-review protocol degrades without
   anything failing. Any such transport must pin the sandbox and hand the payload
   over in an isolated directory — a new requirement this repo has never had.
3. **Quota exhaustion is a failure mode we have never handled.** Today Sol fails
   on an HTTP error and exits 5. A quota-exhausted subscription is a different
   condition that deserves a distinct exit code and a distinct tracker response,
   or it will present as a transport failure and get retried.

This is the same treatment `docs/osmani-audit.md` §1.4.7 gave the dark lane:
specified enough that the next person does not start from zero, and explicitly
not started.

---

# §6 — Adoption backlog

Ranked. Item 1 is a live defect; item 2 is the only one that can reorder the
rest. Nothing here is built.

Re-ranked after §7. The top three no longer involve the subscription at all,
because §7 found cheaper and more useful work on a resource already paid for.

| # | Item | Target | Size | Eval? |
|---|---|---|---|---|
| 1 | ~~Fix the dead `mimo` alias~~ **done** on `worktree-openrouter-alias` (`c8971c0`, repointed to `xiaomi/mimo-v2.5`); refreshing `kimi`/`minimax` to the 1M-context generation is still open (§7.4) | `scripts/call_openrouter.sh` | trivial | see §7.4 |
| 2 | The adversary bake-off: 2–3 specs at their pre-fix commits through Sol, GLM 5.2, DeepSeek V4 Pro; score against the findings each Revision log records (§7.5) | none (experiment, ~$0.29) | small | no |
| 3 | Require a code location on every adversary finding via `structured_outputs` (§2.2, §7.3) | `scripts/call_sol.sh`, `validate_envelope.jq` | small | yes |
| 4 | Route Sol through OpenRouter — `--via` transport reusing the adversary/reviser prompts, `:batch` for unattended stages (§7.1) | `scripts/call_sol.sh` | medium | yes |
| 5 | Re-ground "no metered tiers unattended" on **quota** rather than dollars (§3.2) | 7 policy sites + `skills/line` | medium | yes |
| 6 | Install the plugin; confirm `/codex:adversarial-review` runs and which model it resolves to | none (verification) | trivial | no |
| 7 | `doctor.sh`: `codex` binary present, logged in, **review gate off** | `scripts/doctor.sh` | small | yes |
| 8 | Name the plugin in the ladder as an attended-only Sol surface, distinct from `call_sol.sh`, carrying the §3.1 distinction | `templates/LOOP_POLICY.md` | small | no |
| 9 | Evaluate `/codex:adversarial-review` as the `profile: hardened` payload (`osmani-audit.md` §2.4.3) | `skills/review`, spec 005 | medium | yes |
| 10 | `codex exec` transport | `scripts/call_sol.sh` | large | yes |
| 11 | Pre-flight cost estimate on shim calls, with a confirmation threshold (§8.3) | `scripts/lib/common.sh`, `scripts/call_openrouter.sh` | small | yes |

**Ordering notes.**

Item 1 is first because it is a live defect, not an improvement. `--model mimo`
resolves to a model OpenRouter does not list, in a scaffolded file, in every
project this plugin has stamped.

Item 2 is the only item that can change the ranking of everything below it, and
it costs about thirty cents. Every "cheaper" claim in §7.2 is a price claim; none
of them is a quality claim. Running it converts the whole of §7 from arithmetic
into evidence.

Item 3 is worth doing **whatever the outcome of item 2**, and whether or not the
subscription is ever bought. It is a mechanism, not a dependency: the plugin's
schema demonstrated that requiring `file` / `line_start` / `line_end` turns "cite
your evidence" from a request into a refusal, and every candidate model supports
the parameter that would enforce it (§7.3).

Item 5 blocks item 10 and nothing else. It is the only item here that is purely a
decision — no code is required to notice that a rule phrased in dollars stops
binding when the dollars stop.

Items 6–9 are the subscription's own track and are now below the free work
deliberately. Item 9 additionally depends on spec 001 (`profile` as a real
switch), itself queued behind spec 004. Nothing in this document jumps that
queue.

---

# §7 — The option we already own: OpenRouter

§4 compared a ChatGPT subscription against an OpenAI API key and found the
subscription buys attended capability rather than autonomy. That comparison was
incomplete. There is a third option already paid for, and it changes the answer.

All figures below were pulled from `https://openrouter.ai/api/v1/models` on
**2026-08-07** and are list prices per 1M tokens at that moment. They are
first-party (OpenRouter's own catalog endpoint), unlike the quota estimates in
§3.3 — but they are a snapshot of a price list that moves.

## 7.1 Sol itself is on OpenRouter, at list price

The finding that reframes everything:

| Model id | $/M in | $/M out | Context |
|---|---|---|---|
| `openai/gpt-5.6-sol` | 5.00 | 30.00 | 1.05M |
| `openai/gpt-5.6-sol:batch` | 2.50 | 15.00 | 1.05M |
| `openai/gpt-5.6-terra` | 1.00 | 6.00 | 1.05M |
| `openai/gpt-5.6-luna` | 0.10 | 0.60 | 1.05M |

`openai/gpt-5.6-sol` is priced identically to the direct API path our shim
already hardcodes (`scripts/call_sol.sh:33-34`), which is consistent with the
OpenRouter shim's own billing note — *"list price + top-up fee, no per-token
markup"* (`scripts/call_openrouter.sh:4`). The `:batch` variant is exactly half.

Three consequences:

1. **Scriptable Sol is available today**, on a balance the owner already holds,
   with no ChatGPT subscription and no `OPENAI_API_KEY`. It reaches the factory
   where §4 established the plugin cannot go.
2. **Batch halves the price for exactly our use case.** The factory's build and
   review stages are unattended and latency-tolerant by construction — *"Terminal
   state is an open PR, never a merge"* (`templates/LOOP_POLICY.md:202`), so the
   work stops and waits for a human regardless. Latency is the thing we have
   most of.
3. **Cost reporting gets more honest, not less.** `call_sol.sh` computes cost
   from two hardcoded constants carrying a *"recalibrate from the OpenAI usage
   dashboard"* comment (`scripts/call_sol.sh:32`) — a number that silently drifts
   when prices change. The OpenRouter shim reads OpenRouter's own reported figure
   (`scripts/call_openrouter.sh:79`). One is an estimate that rots; the other is
   what was actually charged.

## 7.2 What a cross-family adversary costs

Two payload profiles, because reasoning tokens are the live uncertainty and
every candidate below bills them as output. **Lean** = 25k in / 4k out. **Heavy**
= 60k in / 20k out, modelling a reasoning-heavy pass over a large diff. The last
two columns are how many such reviews USD 30 buys.

| Model | $/M in | $/M out | Context | Lean | Heavy | Lean/$30 | Heavy/$30 |
|---|---|---|---|---|---|---|---|
| `deepseek/deepseek-v4-flash` | 0.14 | 0.28 | 1.05M | $0.005 | $0.014 | 6493 | 2142 |
| `openai/gpt-5.6-luna` | 0.10 | 0.60 | 1.05M | $0.005 | $0.018 | 6122 | 1666 |
| `minimax/minimax-m3` | 0.30 | 1.20 | 1.05M | $0.012 | $0.042 | 2439 | 714 |
| `deepseek/deepseek-v4-pro` | 0.435 | 0.87 | 1.05M | $0.014 | $0.044 | 2089 | 689 |
| `xiaomi/mimo-v2.5-pro` | 0.435 | 0.87 | 1.05M | $0.014 | $0.044 | 2089 | 689 |
| `mistralai/mistral-large-2512` | 0.50 | 1.50 | 262k | $0.019 | $0.060 | 1621 | 500 |
| `z-ai/glm-5.2:batch` ⚠ | 0.70 | 2.20 | 512k | $0.026 | $0.086 | 1140 | 348 |
| **`z-ai/glm-5.2`** | 0.5026 | 1.5796 | 1.05M | $0.019 | $0.062 | **1588** | **485** |
| `x-ai/grok-4.3` | 1.25 | 2.50 | 1.00M | $0.041 | $0.125 | 727 | 240 |
| `openai/gpt-5.6-terra` | 1.00 | 6.00 | 1.05M | $0.049 | $0.180 | 612 | 166 |
| **`qwen/qwen3.8-max`** | 2.00 | 6.00 | 1.00M | $0.074 | $0.240 | **405** | **125** |
| `x-ai/grok-4.5` | 2.00 | 6.00 | 500k | $0.074 | $0.240 | 405 | 125 |
| `openai/gpt-5.6-sol:batch` | 2.50 | 15.00 | 1.05M | $0.123 | $0.450 | 244 | 66 |
| `moonshotai/kimi-k3` | 3.00 | 15.00 | 1.05M | $0.135 | $0.480 | 222 | 62 |
| **`openai/gpt-5.6-sol`** | 5.00 | 30.00 | 1.05M | $0.245 | $0.900 | **122** | **33** |

Read against Sol as the baseline: GLM 5.2 is **13×** cheaper, Qwen 3.8 Max
**3.3×**, DeepSeek V4 Pro **17×**, DeepSeek V4 Flash **53×**. Grok 4.3 is 6×
cheaper and adds a fourth model family. Kimi K3 is only 1.8× cheaper and is the
weakest value on this list.

**These prices move faster than this document does, and that is measured, not
assumed.** The catalog was fetched twice on 2026-08-07, hours apart. Two of 400
models repriced in between: `moonshotai/kimi-k2.6` slightly, and **`z-ai/glm-5.2`
by 34%** — from $0.76/$2.42 to $0.5026/$1.5796. The table above carries the
second fetch. The first draft of this section carried the first, and every
derived figure in it was wrong within a day.

Two consequences worth acting on rather than noting:

- **Re-fetch before quoting any of this.** A 34% single-day move on the
  document's headline recommendation is not a rounding concern.
- **The `:batch` shortcut is not reliably a discount.** `z-ai/glm-5.2:batch`
  stayed at $0.70/$2.20 while the standard variant repriced beneath it, so batch
  is now **more expensive** than the model it is supposed to discount. It
  remains half price for `openai/gpt-5.6-sol` (§7.1). Anything that reaches for
  `:batch` automatically should compare, not assume.

The honest caveat, stated before the backlog leans on these numbers: **this table
measures price, not quality.** Nothing here says GLM 5.2 finds what Sol finds.
That is the experiment, and §7.5 is how to run it.

## 7.3 Every candidate can enforce an evidence contract; Sol currently does not

§2.2 found that the Codex plugin's schema is stricter than ours — it *requires*
`file`, `line_start`, `line_end` on every finding, so a claim without a code
location cannot be emitted. Ours asks for evidence in prose
(`scripts/call_sol.sh:61-62`), which a model can decline.

Every model in §7.2 advertises both `structured_outputs` and `response_format`
in its OpenRouter `supported_parameters`. Our current Sol path uses neither: the
request at `scripts/call_sol.sh:92-99` sends `model` / `instructions` / `input` /
`reasoning` and no schema, then recovers JSON by best-effort text slicing
(`scripts/lib/common.sh:186-199`).

So a $0.03 GLM 5.2 review could carry a **stricter** evidence contract than our
$0.25 Sol review does today. That is an argument for backlog item 3 independent
of which model wins — the gap is in our request construction, not in the model.

## 7.4 Our OpenRouter aliases have rotted, and one is dead

Checked against the catalog rather than assumed:

| Alias | Configured id | Status |
|---|---|---|
| `mimo` | `xiaomi/mimo-v2` | **not in the catalog** — the call fails |
| `kimi` | `moonshotai/kimi-k2` | alive, 131k context; `kimi-k3` is 1.05M |
| `minimax` | `minimax/minimax-m2` | alive, 205k context; `minimax-m3` is 1.05M |

The `mimo` default at `scripts/call_openrouter.sh:41` resolves to a model
OpenRouter no longer lists, so `--model mimo` is broken until overridden via
`OPENROUTER_MODEL_MIMO`. This is a scaffolded file, so it is broken in every
project the plugin has stamped.

The context figures matter more than the version numbers. `build_task_prompt`
inlines every `--input-path` wholesale (`scripts/lib/common.sh:147-157`); a 131k
window is a real ceiling on whole-diff review, and the current generation is
eight times larger.

## 7.5 The decision, restated with three options

| Option | ~USD 30 buys | Scriptable? | Scope |
|---|---|---|---|
| ChatGPT Plus | attended reviews, quota-capped, unusable beyond human attention (§3.3) | **No** | diff, no spec |
| OpenAI API key | ~122 lean Sol reviews | Yes | spec + candidate |
| **OpenRouter (already owned)** | the same Sol at the same price, or 244 at batch, or 1588 GLM 5.2 | Yes | spec + candidate |

**OpenRouter dominates the API-key option** — same model, same price, one fewer
credential, honest cost reporting, and model choice on top. There is no case for
adding `OPENAI_API_KEY` when `OPENROUTER_API_KEY` reaches the same model.

**Against the subscription the comparison is not about price at all.** The
subscription buys a *different* review — attack-surface, diff-scoped, attended
(§3.1) — which is why §6 item 9 proposes it as the `hardened` payload rather
than as a Sol replacement. It should be judged on whether that second opinion is
worth ~USD 30, not on review volume, where it loses to a resource already paid
for.

**The experiment worth running is now cheap enough to be uninteresting to
budget — but it has to be run against ground truth that exists.** An earlier
draft of this section proposed scoring against "the blind review a built spec
received." There are no built specs: all thirteen in `factory/specs/` are
`queued` or `shelved`, so no diff and no build-stage review exists to score
against. The proposal was unrunnable and is recorded here rather than quietly
replaced.

What *does* exist is the **spec-review** gate's output. Specs 001–014 each carry
a Revision log recording exactly what the blind spec-reviewer found and what
changed in response — for example `factory/specs/014-spec-internal-consistency.md`
records five findings, one of which disproved the spec's own primary check. Git
history holds each spec as it stood before those fixes landed.

So the runnable bake-off is: take two or three specs at their pre-fix commits,
send the identical adversary brief through `openai/gpt-5.6-sol`, `z-ai/glm-5.2`
and `deepseek/deepseek-v4-pro`, and score each against the findings that spec's
Revision log actually records. Ground truth is written down, dated, and was
produced by a reviewer that had no access to these models' answers.

Cost at lean-profile rates is roughly **$0.28 per spec across all three** — Sol
$0.245, GLM $0.019, DeepSeek $0.014 — so three specs is under a dollar. The
question it answers is the only one that matters and the only one this document
cannot: does a 13×-cheaper model miss what Sol catches?

Two cautions on reading the result. The scoring is against what one blind
reviewer found, not against what was *there* — a model finding something the gate
missed scores as a false positive under this rubric and may not be one. And a
single spec is a sample of one; three is a sample of three. This experiment can
cheaply falsify "the cheap model is adequate"; it cannot establish it.

Until it runs, nothing here recommends demoting Sol. Price is not evidence.

## 7.6 Benchmarks, and what they do not say

§7.2 ranks by price. This ranks by measured capability, and the two orders are
not the same.

The best cross-model reference covering all these families is the **Artificial
Analysis Intelligence Index**, snapshot **2026-08-07**. Read it with its own
disclaimer attached: the index *"aggregates provider-reported and
benchmark-derived signals into a single model-level score"* — so "independent"
here means independently *assembled*, not independently *re-run*.

| Model | AA Index | Verified coding signal | $/M in | $/M out |
|---|---|---|---|---|
| Claude Opus 5 | 60.7 | — | n/a (subscription) | n/a |
| Claude Fable 5 | 59.9 | — | n/a | n/a |
| `openai/gpt-5.6-sol` | 58.9 | — | 5.00 | 30.00 |
| `moonshotai/kimi-k3` | **57.1** | **#1 Arena Frontend Coding**, 1,679 Elo / 483,895 blind votes | 3.00 | 15.00 |
| `openai/gpt-5.6-terra` | 55.0 | — | 1.00 | 6.00 |
| `x-ai/grok-4.5` | 53.8 | — | 2.00 | 6.00 |
| `openai/gpt-5.6-luna` | 51.2 | — | 0.10 | 0.60 |
| `z-ai/glm-5.2` | **51.1** | **#1 globally on Code Arena and Design Arena** (arena-style ranking; my sources report no vote count or Elo for it) | 0.5026 | 1.5796 |
| `deepseek/deepseek-v4-flash` | 49.9 | — | 0.14 | 0.28 |
| `qwen/qwen3.7-max` | 46.0 | SWE-bench Verified 80.4 (third-party) | — | — |
| `minimax/minimax-m3` | 44.4 | — | 0.30 | 1.20 |
| `deepseek/deepseek-v4-pro` | 44.3 | SWE-bench Verified ~80.6 (third-party tracker) | 0.435 | 0.87 |
| `x-ai/grok-4.3` | 37.6 | — | 1.25 | 2.50 |
| **`qwen/qwen3.8-max`** | **not scored** | **none** | 2.00 | 6.00 |

**Vendor-reported figures, kept separate because they are marketing until
someone re-runs them.** Terminal-Bench 2.1: Kimi K3 88.3, Opus 4.8 85.0, DeepSeek
V4 Flash 82.7, GLM 5.2 81.0. SWE-bench Pro: GLM 5.2 62.1, DeepSeek V4 Pro 55.4
("unverified scaffold"). Kimi K3 self-reports SWE-bench Verified ~78 and
HumanEval 88.3. Security: **Cybergym — DeepSeek V4 Flash 76.7 against Opus 4.8
83.1**, published by DeepSeek, which is a vendor conceding a loss and therefore
more trustworthy than the reverse.

Three findings from this table that the price table hides:

**The model named in the request has no third-party score at all.** Qwen 3.8 Max
(released 2026-07-19, 2.4T params / 95B active) is absent from the AA snapshot.
Everything Alibaba has published is narrative — cash returned in an e-commerce
simulation, gate counts in a chip-design run, commits and PRs over an autonomous
fortnight. Those are demonstrations, not benchmarks; nothing in them is
comparable to another model. At $2.00/$6.00 it is among the more expensive
options here — dearer than everything except Kimi K3, level with Grok 4.5 — and
the only one with nothing to check. **It cannot be recommended
on evidence**, which is a statement about the evidence rather than the model.

**The cheaper DeepSeek is the better DeepSeek.** V4 Flash scores 49.9 against V4
Pro's 44.3 while costing roughly a third as much. Pro's counter-argument is a
~80.6 SWE-bench Verified figure from a third-party tracker where Flash's is
unreported — so the two disagree depending on which benchmark you privilege. On
everything measured *the same way for both*, Flash wins and is cheaper.

**Nothing here measures adversarial review.** Code Arena and Arena Frontend
Coding measure human preference between generated outputs. SWE-bench measures
whether a patch makes a test pass. Neither asks "did it find the defect somebody
else shipped," which is the entire job in §3.1. This is precisely why §7.5's
bake-off is item 2 and not item 9: for the review use case specifically, the
leaderboards are the wrong instrument and there is no substitute for running it.

---

# §8 — A second OpenRouter account for overflow

The stated plan is a separate OpenRouter account for inference when Claude limits
are hit, with a cost estimate up front. The economics work. One structural
constraint has to come first, because it determines what the account can cover.

## 8.1 It cannot back-fill the Claude Code session itself

Switching models when Claude limits are hit does not mean Claude Code starts
running GLM 5.2. Pointing Claude Code at another provider is exactly the
`ANTHROPIC_BASE_URL` redirection of §1 — the method the owner rejected, and the
one that violates Anthropic's Consumer Terms.

What a second account genuinely buys is **delegated** capacity:

- The shim tier that already exists — `scripts/call_openrouter.sh`, wired into
  the ladder at `templates/LOOP_POLICY.md:17` as *"cheap bulk generation/second
  opinions"*, and reachable from any stage.
- The factory's unattended workers, where the model is chosen per call anyway.
- A different client entirely (Codex CLI, or any editor that speaks OpenRouter)
  if interactive work is what ran out — a separate tool, not a re-skinned
  Claude Code.

So the honest framing is an **overflow budget for work you delegate**, not a
failover for the seat you sit in. That distinction decides whether the account is
worth opening: if the limit being hit is the interactive session, this helps only
insofar as more work can be pushed down to shims.

## 8.2 Picks by task class

Costs use four payload profiles: **review** 25k in / 4k out, **implementation**
40k / 12k, **planning** 15k / 8k, **security audit** 60k / 10k.

| Task class | Pick | Cost/task | Per $30 | Confidence |
|---|---|---|---|---|
| Implementation | `z-ai/glm-5.2` | $0.039 | 768 | **Medium-high** — #1 Code Arena *and* Design Arena, third-party; no vote count published |
| Review (adversarial) | `z-ai/glm-5.2` | $0.019 | 1588 | **Low** — no benchmark measures this; run §7.5 |
| Security hardening | *stay on frontier* | — | — | **Do not substitute** — see below |
| Planning / architecture | `moonshotai/kimi-k3` | $0.165 | 181 | **Medium** — AA 57.1, the smallest gap to Sol |

**Implementation → GLM 5.2.** It holds the #1 position on both Code Arena and
Design Arena on blind human votes, which is the single most relevant verified
signal available, and it does it at 13× less than Sol with a 1.05M context.
Kimi K3 is the better model (AA 57.1 vs 51.1, #1 Arena Frontend Coding) but costs
$0.30/task against GLM's $0.039 — nearly eight times more for six index points,
and only 1.8× below Sol. GLM is the value pick by a wide margin; Kimi is the pick
only if a specific task keeps failing on GLM.

**Review → GLM 5.2, held loosely.** Same model, and the honest confidence is
low: §7.6 established that no published benchmark measures defect-finding on
somebody else's diff. Cost is not the deciding factor at $0.029 a call — the
bake-off is.

**Security → do not substitute.** This is the one class where the
recommendation is to keep paying. The only published security number across
these models is Cybergym, where DeepSeek V4 Flash reaches 76.7 against Opus
4.8's 83.1 — and GLM 5.2 has no published Cybergym result at all. Security is
also the class `docs/osmani-audit.md` §2.4.3 already identifies as our *depth*
gap rather than our coverage gap, so substituting a cheaper model attacks the
wrong problem. If anything, run DeepSeek V4 Flash **in addition** at $0.011 an
audit — as a second pair of eyes it is nearly free, and a disagreement between
it and the frontier model is a signal worth having.

**Planning / architecture → Kimi K3, and this is where not to economise.** The
AA spread is Opus 5 60.7, Sol 58.9, Kimi K3 57.1, GLM 5.2 51.1. Planning errors
do not stay local — they propagate into every task downstream, which is the one
place where saving $0.13 can cost hours. Kimi K3's price is hard to justify
anywhere else on this list and easy to justify here: half of Sol's cost for 1.8
index points.

**Qwen 3.8 Max is not picked for anything**, per §7.6 — not on quality grounds
but on evidentiary ones. Revisit when a third party scores it.

## 8.3 Estimating cost before the call

The shim already reports what a call *actually* cost, straight from OpenRouter
rather than from a hardcoded constant (`scripts/call_openrouter.sh:79`). What
does not exist is an estimate *before* it runs.

It is a small, well-defined gap: token-count the assembled prompt, multiply by
the catalog price for the resolved model, print the figure, and require
confirmation above a threshold. Every input is already available —
`build_task_prompt` produces the exact string that will be sent
(`scripts/lib/common.sh:138-159`), and OpenRouter publishes per-model prices at
the catalog endpoint. The only genuinely new thing is a token estimate, and a
character-count heuristic is honest enough for a pre-flight warning provided it
is labelled as an estimate rather than reported as a cost — the distinction
`scripts/lib/obs.sh:18-19` already insists on.

That is backlog item 11, and it is a prerequisite for spending on a second
account with any discipline: without it, "cheap per call" is a claim nobody
checks until the invoice.

## Sources

- Valletta Software, "Run GPT-5.6 in Claude Code" —
  https://vallettasoftware.com/blog/post/run-gpt-5-6-in-claude-code
  (the prompt for this analysis; method rejected in §1)
- OpenAI, `codex-plugin-cc` — https://github.com/openai/codex-plugin-cc
  pinned at `db52e28f4d9ded852ab3942cea316258ae4ef346` (2026-07-08), plugin v1.0.6
- `openai/codex` issue #32606, "GPT-5.6 Terra and Sol exhaust the 5-hour Codex
  usage limit within minutes" — https://github.com/openai/codex/issues/32606
  (open at time of writing)
- Codex CLI documentation — https://learn.chatgpt.com/docs/codex/cli
- Third-party quota estimates (§3.3, **unconfirmed at source** — OpenAI's own
  help pages return HTTP 403 to fetches):
  https://simplemetrics.xyz/chatgpt-codex-limits-2026/
- OpenRouter model catalog and list prices (§7) —
  https://openrouter.ai/api/v1/models, fetched twice on 2026-08-07. First-party,
  and demonstrably volatile: `z-ai/glm-5.2` repriced 34% between the two fetches
  (§7.2). Re-fetch before relying on any figure in §7.2, §7.6 or §8.2.
- Artificial Analysis Intelligence Index, snapshot 2026-08-07 (§7.6), read via
  https://benchlm.ai/benchmarks/artificialanalysis — a secondary rendering of AA's
  leaderboard, cross-checked against a second secondary source below where the
  two overlap (Kimi K3 57/57.1, GLM 5.2 51/51.1, DeepSeek V4 Flash 50/49.9). The
  index's own description says it aggregates *provider-reported* alongside
  benchmark-derived signals.
- Model comparison and vendor-reported benchmark tables (§7.6) —
  https://a2aprotocol.ai/insights/qwen-38-max-vs-glm-52-vs-kimi-k3-vs-deepseek-v4-flash
  and https://www.developersdigest.tech/blog/glm-5-2-vs-deepseek-v4-vs-qwen3-open-weights-coding-showdown
  Both secondary. Every figure sourced from them is labelled vendor-reported or
  third-party in §7.6; **none was re-run here**, and no benchmark in this
  document was executed by us.

Internal: `docs/osmani-audit.md` (§2.4.3 names the `hardened` gap this plugin
would fill), `docs/factory.md` (the stage contracts §4 would touch),
`docs/observability-architecture.md` (the cost plane §3.2 argues goes blind).

---

*This document assesses a purchase; it does not make one, and it changes nothing
in the factory. Everything in §6 is unbuilt. The scripted transport of §5 is
specified precisely so that it can be declined on the record rather than drifted
into.*

*§7 was added after the rest and inverted the backlog. That is worth recording as
a process note rather than editing away: the first six sections compared the two
options the question named, and the better answer was a third option nobody had
named, already paid for. The cost tables in §7.2 are still only prices — the only
item that turns them into a recommendation is the bake-off, and it has not been
run.*
