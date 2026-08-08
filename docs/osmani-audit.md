# Graded Against the Outside: Osmani's Light/Dark Factories and Skills Catalog

Every other document in `docs/` explains what this factory *is*. This one grades
it against somebody else's standard.

Two artifacts by Addy Osmani bear directly on this repo. The first is the essay
**"Software Factories: Light and Dark"**, which names a three-layer structure
(loop → harness → factory), argues that verification rather than generation is
the binding constraint, and frames autonomy as a per-loop switch you deliberately
set rather than a level you globally choose. The second is
**[`addyosmani/agent-skills`](https://github.com/addyosmani/agent-skills)** (MIT),
a 24-skill pack covering Define → Plan → Build → Verify → Review → Ship.

`docs/software-factory-analysis.md` already cites Osmani's *Loop Engineering* as
an input to this design. The essay is the natural successor, and it is the first
external framework specific enough to be used as a **rubric** rather than an
inspiration. That is how it is used here.

Part 1 contrasts the essay against what we built. Part 2 audits the catalog
against our coverage and decides what is worth promoting. Both are deliberately
adversarial toward this repo: the twelve places we pass are compressed into one
section, and the four places we fail get the space.

Two ground rules, both inherited from the repo's own principles:

- **Every claim about our system carries a `file:line`.** Nothing here is
  asserted from memory.
- **Nothing gets adopted as prose.** Our first principle is *"Gates, not
  documentation"* (`README.md:146`). Importing a prose skill would violate the
  exact rule this repo exists to enforce, so every adoption in Part 2 is
  specified as a gate, an injected checklist, or a spec field.

Osmani's positions below are paraphrased with attribution rather than quoted at
length; short terms of art (`dark factory`, `comprehension debt`, `back
pressure`) are his and are kept verbatim because renaming them would lose the
reference.

---

# Part 1 — The essay, contrasted

## 1.1 The structural mapping

Osmani's three layers land on this codebase almost one-to-one. This is worth one
table and no more — structural agreement is the least interesting finding here.

| Osmani's layer | His definition, paraphrased | Ours |
|---|---|---|
| **Loop** | one agent doing a single job on repeat — gather context, act, check, iterate | `templates/LOOP_POLICY.md` — tier ladder (`:9–20`), the 6-field delegation brief (`:87–97`), the worker envelope contract |
| **Harness** | the walls around a loop: sandbox, tools, memory, and the gates that define "done" | `scripts/lib/*.sh` (`tracker.sh`, `usage_gate.sh`, `workflow.sh`, `scaffold.sh`), `hooks/hooks.json`, worktree-per-spec isolation, and `check_cmd` as the completion oracle |
| **Factory** | many harnessed loops, fed by a queue, drained through a review gate into production | `factory/specs/` as the queue, `templates/workflows/factory.js` as the scheduler, `skills/spec\|build\|review` as the stages, the human as the review gate |

The interesting part is that we arrived here from a different direction — the
design notes in `docs/software-factory-analysis.md` trace the shape to a posted
workflow and to VSDD, not to this essay. Convergent structure is mild evidence
that the shape is forced by the problem rather than chosen by taste.

## 1.2 Where we already satisfy the rubric

Compressed deliberately. Each line is a claim of the essay's, followed by the
mechanism in this repo that satisfies it.

**Back pressure — autonomy is bounded by verifiability.** Every hinge in our
pipeline is a non-LLM check. The Red Gate requires the test to fail before any
implementation exists — *"Run `check_cmd`; it MUST fail"* (`skills/build/SKILL.md:46`),
and a check that already passes on the untouched tree marks the spec `blocked`
rather than building anyway (`:47–49`). Done-ness is an exit code, never a
claim: *"A completion signal that isn't the model's opinion"* (`docs/factory.md:38`).
The reviewer re-runs the suite itself instead of trusting the builder —
*"reviewer claims without a non-LLM check are opinions"* (`skills/review/SKILL.md:53`).

**No self-grading.** `docs/factory.md:26` states the failure mode in the essay's
own terms: a worker that grades its own homework always passes. The structural
answer is the blind-review protocol — the reviewer receives the spec and the
diff, never the builder's reasoning (`skills/review/SKILL.md:41–44`).

**The attention budget.** Osmani cites Dex Horthy's rule of thumb that an agent
holds up for roughly three to ten steps and starts losing the thread past twenty.
We bound in four independent places: one spec per `build` invocation, a
progress-based revision cap of 2 (`templates/LOOP_POLICY.md:79`), `MAX_ITER=5`
in `scripts/run_headless.sh:38`, and a spawn guard that refuses more than six
subagent spawns in sixty seconds (`templates/hooks-spawn-guard.json`).

**Humans own the outer loop, and the boundary is evidence.** Osmani argues the
handoff between agent and human should be diffs, tests, logs, and a short
explanation connecting them. Our PR body is specified as exactly that: executive
summary, acceptance checklist with pass/fail, a mandatory test plan with one
checkbox per acceptance criterion, an explicit "not verified in this environment"
section, caveats, and the spec reference (`skills/review/SKILL.md:88–152`).

**We cannot go dark by construction.** *"Terminal state is an open PR, never a
merge"* (`templates/LOOP_POLICY.md:202`).

Three things we do that the essay does not cover, worth naming because they are
where this repo is ahead of its rubric:

1. **Saturation self-throttling.** `scripts/lib/usage_gate.sh` postpones new
   claims once a subscription window crosses 90%. The essay treats cost as a
   constraint but proposes no mechanism.
2. **Mutation-tested guards.** *"A guard whose test passes with the guard
   deleted is not a guard"* (`docs/factory.md:666`). Every safety check has an
   eval, and each eval is verified by deleting the check and confirming failure.
3. **Sub-file ownership.** Region-marked spans in `.claude/workflows/factory.js`
   let a project customize its line without forking away from safety updates
   (`README.md:156–159`) — a distribution problem the essay does not reach.

## 1.3 The four places we fail

### (a) We have no switch

The essay's closing claim is that the skilled job is deciding where to put each
switch — per loop, by oracle strength and consequence. That framing assumes
switches exist.

We have one policy and apply it to everything. Every spec gets the same grilling
gate, the same Red Gate, the same blind review, the same revision cap, the same
terminal state. `profile:` exists in the spec frontmatter
(`templates/factory-spec.md:5`, defaulting to `standard`) and is referenced in
exactly one place in the entire codebase — `skills/spec/SKILL.md:98`, which tells
the spec skill to write `profile: hardened` if the user asks for it. Nothing
reads it. `scripts/lib/tracker.sh:11` lists it as a frontmatter key it preserves.
It routes nothing, gates nothing, and changes no behavior.

Being uniformly lit is safe. It is not the essay's thesis. It is the absence of a
decision rather than a decision, and it costs us in both directions: trivially
verifiable work carries ceremony it does not need, and genuinely dangerous work
gets no more scrutiny than a typo fix.

### (b) `effort_budget` measures size, not stakes

Our only spec-level dial is `effort_budget: trivial | small | medium | large`,
which *"drives grilling depth and tier routing"* (`templates/factory-spec.md:29`).
That is a **size** axis: how much work is this, how many tool calls will it take.

Osmani's axis is **consequence**. His examples are explicit — an auth system, a
billing engine, or a public API contract are things you do not want to wake up
to broken, and they stay human-reviewed regardless of how small the change is; a
nightly cron that fixes one anti-pattern can run on its own regardless of how
many files it touches.

Size and consequence are orthogonal, and we only measure one. A trivial-but-
irreversible change (drop a column, rotate a credential format, change a public
error code) and a large-but-cosmetic one (reformat 200 files) receive identical
treatment today. This is the single most actionable gap in this document, and it
is a one-field fix.

### (c) Comprehension debt is asserted, not measured

Osmani's core failure mechanism — `comprehension debt`, the widening gap between
how much code exists and how much any human still understands — is the thing a
factory accrues silently while every test stays green.

We address it indirectly and in several places: the `minimize` ladder pushes
against volume, the reviewer's guard checklist flags premature abstraction
(`agents/reviewer.md:36–47`), the PR test plan forces the change to be explained
in reviewable terms, and the evening digest keeps the human in contact with what
shipped.

But we just built an entire observability plane — capture, derive, and export —
that measures cost, latency, error rate, tokens per spec, cycle time, and re-open
rate, and measures **nothing about comprehension**. That is a notable omission
for a system whose stated purpose includes auditing how projects actually
operate (`docs/roadmap.md:23–32`).

Four proxies are already derivable from the existing event log, with no new
capture:

| Proxy | Signal | Source |
|---|---|---|
| Diff size per spec | volume shipped per unit of human attention | `tracker_transition` + git |
| Review-finding density | how much the blind reviewer had to say per KLOC | review-stage events |
| Human merge latency | the `pr-open → done` segment — already captured as segment two of cycle time | `tracker_transition` timestamps |
| Re-open rate | lagging indicator: work the human did not actually understand the first time | transitions back into `building` |

Naming this as a missing **metric family** is a stronger finding than adding one
metric blind. It is item 7 in the backlog, and it is a prerequisite for §1.4.

### (d) Architecture-for-oversight is unenforced

Osmani argues that good types, test seams, legible structure, short call stacks,
clear component boundaries, and dependency injection are what make human
oversight *cheap* — and that the model will not supply them, because the agents
that feel most capable are trained against their own harness and tools rather
than for long-term maintainability.

Our reviewer is explicitly scoped away from this: *"Report ONLY correctness and
requirement gaps. Not style, not taste, not hypothetical improvements"*
(`agents/reviewer.md:25–27`). The reasoning is sound and evidence-backed — a
reviewer asked for findings will always produce some, and chasing them causes
over-engineering. But the consequence is that **nothing in our pipeline defends
legibility.**

The `minimize` ladder is not a substitute. It makes code *smaller*, which is a
different property from *legible* — a dense one-liner satisfies `minimize` and
fails oversight. And the ladder's own hard exception (never trim validation,
error handling, or security to get smaller, `agents/worker-cheap.md:34`) shows we
already know smallness is not the terminal goal.

This is the hardest of the four to fix without reintroducing the over-engineering
failure the reviewer scoping was designed to prevent, which is why it is *not* in
the adoption backlog as its own item. The honest position: we have a real gap and
no cheap gate for it. The two partial mitigations that are cheap — Chesterton's
Fence before deletion, and the presumptive-blockers list — are in §2.3.

## 1.4 The fork: a dark lane, specified

The essay permits dark loops where the oracle is unfakeable and the blast radius
is bounded; a nightly cron that fixes one anti-pattern is his example. We forbid
all merges unconditionally (`templates/LOOP_POLICY.md:202`).

On the essay's own terms, our blanket rule is over-conservative for trivially
verifiable classes. Rather than record that as an unresolved tension, this
section **specifies** a narrow dark lane. It is a design, not an implementation —
it sits last in the backlog, and §1.4.7 argues against building it yet.

### 1.4.1 The reframe that makes it tractable

Our rule conflates two different autonomies.

We already have **loop autonomy**: `build` and `review` run unattended today,
claiming specs, writing code, running suites, opening PRs, with no human present.
What we forbid is **merge autonomy** — and merge autonomy is the only thing the
essay's `dark factory` actually names: code shipping that no human has read,
verified only by machines.

So the fork is not a second pipeline. It is **the same pipeline plus one
conditional terminal transition, `pr-open → done`, gated by a predicate.** Same
grilling gate, same Red Gate, same blind review, same PR body. Only the last step
differs.

This is the load-bearing architectural decision. The repo's own second lesson is
that whole-file ownership forces forks, and *"the fork silently lost a safety
rule"* (`README.md:156–159`). A parallel dark pipeline would be that failure by
construction. A subset of the lit path with one extra transition cannot drift,
because there is nothing separate to drift.

### 1.4.2 The switch — which also closes gaps (a) and (b)

`profile:` is already in the frontmatter and already dead. It becomes the switch,
with three positions. `effort_budget` keeps meaning size; `profile` starts
meaning consequence. Two orthogonal axes, which is what §1.3(b) said was missing.

| `profile` | Oracle | Review depth | Terminal state |
|---|---|---|---|
| `dark` | pre-existing, unfakeable (§1.4.3) | blind review still runs | machine merges |
| `standard` (default) | spec-authored `check_cmd` + Red Gate | blind review | open PR — human merges |
| `hardened` | as `standard`, plus the security payload of §2.4.3 | blind review + threat model | open PR — human merges |

Note the asymmetry: `dark` does not skip review. It skips the *human*. The
reviewer, the suite, and the PR body all still run — what changes is who presses
merge. That keeps the dark lane's artifact trail identical to the lit lane's,
which §1.4.6 depends on.

### 1.4.3 The eligibility predicate

Six clauses. **All must hold**, and each is written to be evaluated by a script
against a spec plus a diff, with no judgment call. A clause that needs an LLM to
decide is not a gate; it is guidance with extra steps.

**1. The oracle pre-exists the change.**
This is the subtle one. The Red Gate proves a `check_cmd` is *non-vacuous* — it
failed before the implementation existed. It does not prove the check is
*sufficient*: a check that fails on an empty implementation can still pass on a
wrong one. For a lit merge that is fine, because a human reads the diff. For a
dark merge it is the whole ballgame.

So the oracle must not be author-written. `check_cmd` may invoke only checks that
existed before the spec was claimed — the project's own suite, a type checker, a
linter with a fixed ruleset — and **the diff must add no test files**.

*Checkable:* `git diff --name-only <base>..<head>` intersected with the project's
declared test-path glob must be empty, and `check_cmd` must not reference a path
introduced by the diff. Both are string operations on committed state.

This clause alone scopes the lane to roughly Osmani's lint-cron example, which is
the correct amount of scope. A change that had to write its own proof is, by
definition, a change whose correctness was not already decidable.

**2. Blast radius is declared, not inferred.**
The spec's `input_paths` must fall entirely inside a path allowlist the human
declares once, in project config. Auth, billing, migrations, CI configuration,
and `scripts/` (the loop's own machinery — a factory that can silently modify its
own gates is not a factory) are never in it.

*Checkable:* set containment. Declared by a human in a committed file, so the
allowlist itself goes through code review.

**3. No dependency or lockfile changes.**
Supply chain is a high-stakes class in Osmani's framing and the subject of a
whole section of his `security-and-hardening` skill. A dependency bump is exactly
the kind of change that *looks* mechanical and is not.

*Checkable:* the diff touches no manifest or lockfile path.

**4. Nothing irreversible.**
No schema migration, no data mutation, no public API surface change. This reuses
the classifier from §2.4.1 rather than duplicating it — the same detector that
routes a migration-shaped spec to `hardened` also disqualifies it from `dark`.

*Checkable:* to the extent the classifier is (see §2.4.1 — pattern matching on
migration directories, DDL statements, and exported-symbol removal). Where the
classifier is uncertain it must answer "irreversible", so this clause fails
closed.

**5. Cheapest tiers only.**
If the work required sonnet-level judgment, it was not mechanical, and a
non-mechanical change does not belong in a lane whose premise is that a machine
oracle is sufficient. Doubles as a cost control.

*Checkable:* every event already carries a `tier`, from both directions —
`obs_tier_from_worker` maps shim workers (`scripts/lib/obs.sh:162–170`) and
`tier_for_agent` maps native subagents (`scripts/observe.sh:92–96`). Assert that
no event above the haiku tier carries this `spec_id`.

**6. No escalation signal on the record.**
A worker that returns `needs_escalation` has declared the situation exceeded
routine handling, which is the opposite of the lane's premise. Such a spec ejects
to lit rather than having the escalation recorded for evening review.

*Checkable — but only partly, and the residual matters.* The observable half is
solid: `needs_escalation` is a worker-envelope status
(`scripts/lib/validate_envelope.jq:12–13`) and envelope status is copied into the
event (`scripts/lib/obs.sh:196`), so "no event for this `spec_id` has
`status == needs_escalation`" is a real query.

The unobservable half is the orchestrator's own trigger evaluation. Three of the
five structural triggers in `templates/LOOP_POLICY.md:54–61` — high-stakes or
irreversible output, material disagreement between reviewers, known-hard
correctness class — are judgments the orchestrator makes internally, and **no
event records them today**. A spec could satisfy this clause as written while an
unrecorded trigger fired.

Two of those three are covered elsewhere: high-stakes/irreversible by clause 4,
repeated-failure and tests-still-failing by the per-spec retry ceiling in §1.4.4.
The genuine residual is *material disagreement between reviewers*, which today
leaves no trace a script can read. So this clause is honestly stated as:
**implementing the lane requires first emitting an event when a structural
trigger fires.** That is a small addition to the build and review stages and it
belongs in item 8's scope, not assumed away.

Naming this rather than waving at it is the point of the exercise — a predicate
clause that cannot be evaluated is not a gate, and this document argues that
distinction is the whole difference between a factory and a folder of good
intentions.

### 1.4.4 Token guardrails

The owner's explicit condition. We are unusually well-placed here, because the
observability plane built in `docs/observability-architecture.md` already
measures every quantity this needs.

**Nightly lane budget.** Cumulative output tokens attributed to `profile: dark`
work, read from the event log via `scripts/observe_metrics.sh` and checked before
each claim. Exceeded → the lane closes for the night and remaining eligible specs
fall back to lit (PR, no merge). Nothing is lost; the work still happens.

**Fail closed — deliberately inverting the usage gate.** `usage_gate.sh` fails
*open* on a missing or stale mirror — *"failing open (install
templates/statusline-usage.sh to enable gating)"* (`scripts/lib/usage_gate.sh:41`,
and again at `:49` and `:54`) — because a broken statusline must not deadlock the
factory. The dark lane must fail **closed**: no readable meter, no unattended
merges.

Stating both rules side by side is the point, because the asymmetry encodes the
actual risk model. Postponing work is cheap and recoverable. Merging unread work
is neither. A gate's failure direction should follow the cost of being wrong, not
a house style.

**Per-spec ceiling, with ejection rather than abort.** A dark spec exceeding N
output tokens or M retries has produced evidence that it is not the trivially
verifiable class it claimed to be. The response is not "stop" and not "raise the
budget" — it is **eject to lit**: finish the work, open the PR, let a human
merge. Cost overrun is treated as a *misclassification signal*, which is a
strictly more useful reading than a budget problem.

**Daily merge cap.** At most K dark merges per day. This one is not a cost
control at all, and the doc should not pretend otherwise: it bounds the *rate* at
which comprehension debt accrues, which is the essay's actual concern and our
§1.3(c) finding. Even perfectly correct merges that no human read accumulate the
gap Osmani names. K is a statement about how much unread-but-shipped code the
operator is willing to owe per day.

### 1.4.5 Approval, in two levels — neither agent-settable

**Lane authorization** (standing, committed): the human turns the lane on per
project and declares the path allowlist, the budgets, and K. This lives in
config, in git, and gets reviewed like code.

This must be **explicitly excluded from `agent_judgment`** in `skills/config`.
That flag currently permits an agent to self-enable a feature per-task when the
flag's entry allows it. A lane that can authorize its own merge autonomy is not
a gate — it is a suggestion an agent makes to itself.

**Arming** (per run, expiring): the lane is armed for one night and disarms
itself. A permanently-on lane is precisely how a lit factory drifts into a dark
one — not by decision, but by nobody revisiting the decision. An expiry forces
the human to keep choosing, and matches the repo's existing instincts (the
observability context TTL, the usage-gate staleness window).

### 1.4.6 The accountability trail

Osmani's objection to dark factories is comprehension debt, not merge risk alone.
A lane that merges safely but silently still fails his test. So the lane must
leave a fully reviewable record *even though nobody reviewed it*:

- **The PR body is still written in full** — test plan, acceptance checklist,
  caveats — and the merge happens *after* the PR is opened, never instead of it.
  The artifact a human would have read exists; they just did not read it yet.
- **The evening digest grows a distinct "merged unattended" section.** The
  human's job shifts from *approve each* to *audit a sample*. That is a real
  reduction in oversight and the digest should present it as one, with counts
  and diffs one click away.
- **Revert rate auto-closes the lane.** A dark merge later reverted or re-opened
  is the single highest-signal event in the entire system: direct evidence the
  predicate admitted something it should not have. A lane revert rate above
  threshold closes the lane until a human re-authorizes it.

That last mechanism is Osmani's `back pressure` implemented literally rather than
quoted: autonomy expands only as fast as demonstrated verifiability supports, and
contracts automatically when it does not. It also depends on the re-open counter
from §1.3(c), which is why comprehension metrics are item 7 and the lane is item
8.

### 1.4.7 Honest cost/benefit — the argument against building this

This is the one proposal in this document that *removes* a safety property, so
the case against it belongs here rather than in a footnote.

- **It is more machinery than the merges save**, unless a recurring, high-volume,
  low-stakes spec class actually exists. Candidates: dependency-bump batches,
  lint sweeps, doc typo fixes, test-flake quarantine. If the operator cannot name
  one from the last month of real specs, the lane is solving a hypothetical.
- **The predicate is itself code that can be wrong.** Six clauses, each a gate,
  each requiring an eval, each requiring the mutation test — remove the clause,
  confirm the eval fails (`docs/factory.md:666`). That is real work, and it is
  work on the machinery rather than on the product.
- **It reduces oversight in a system whose main claim is oversight.** For a solo
  operator, the blast radius of a bad merge is not distributed across a team that
  might catch it; the $400-overnight-loop failure class
  (`docs/software-factory-analysis.md:36`) is a reminder that unattended systems
  fail in ways their designers did not model.

The argument *for* building it is completeness of the framework, not urgency: it
turns "we forbid this" into "we permit this under stated conditions", which is a
better answer to a peer asking why. That is a real but modest benefit, and it is
why the lane is item 8 of 8.

---

# Part 2 — The skills catalog, audited

## 2.1 Method

Every skill in `addyosmani/agent-skills` gets one of three verdicts:

- **Covered** — we have an equivalent. Usually stronger, for one recurring
  reason: ours is mechanically enforced and his is prose.
- **Steal a mechanism** — the skill as a whole is redundant, but one specific
  device inside it is worth absorbing into a gate we already have.
- **Real gap** — something an unattended loop can get *wrong* in a way our
  current gates would not catch.

The bar for "real gap" is deliberately high. "We don't have a document about X"
is not a gap. "A spec doing X would sail through our pipeline green and be
wrong" is.

All 24 skills share one anatomy: frontmatter → Overview → When (not) to Use →
numbered Process → a **Common Rationalizations** table (excuse → rebuttal) →
**Red Flags** → **Verification**. That format is itself the most portable thing
in the repo, and §2.6 returns to it.

## 2.2 Covered — do not promote (8)

| Skill | Our equivalent | Why ours holds |
|---|---|---|
| `spec-driven-development` | `skills/spec` + `templates/factory-spec.md` | This is the ceremony we measured and rejected — ~8 files / ~1,300 lines for a trivial change (`docs/software-factory-analysis.md:51`). Ours emits one file, always, and gates on `check_cmd` rather than on artifact count |
| `test-driven-development` | The Red Gate | His is red-green-refactor as discipline; ours is an exit code that blocks the stage (`skills/build/SKILL.md:46`). Same idea, ours cannot be skipped. His "discover the stack first" rule is genuinely good and already implicit in our per-project `check_cmd` |
| `planning-and-task-breakdown` | `agents/planner.md` + `depends_on` in `tracker.sh` | Ours decomposes into tier-assigned briefs and enforces ordering mechanically; unmet dependencies are unclaimable, satisfied only by `done` |
| `incremental-implementation` | One spec per `build` invocation, worktree-isolated | Structural rather than advisory |
| `context-engineering` | `templates/LOOP_POLICY.md` tier ladder + 6-field brief + blind payloads | We solve the same problem by *constraining what each worker receives*, which is enforceable, rather than by advising how much context to load |
| `git-workflow-and-versioning` | Worktree per spec, `claude/idea-<slug>` branches, specified PR body | Covered, and ours is checked at the review stage |
| `observability-and-instrumentation` | The whole of `docs/observability-architecture.md` | His is generic app instrumentation (RED/USE, cardinality, two-tier alerting). Ours is agent-specific. See §2.2.1 |
| `using-agent-skills` | `templates/LOOP_POLICY.md` non-negotiables | His six "core operating behaviors" (surface assumptions, manage confusion, push back, enforce simplicity, scope discipline, verify don't assume) are already our policy — e.g. *"Report outcomes faithfully: failing tests are reported as failing"* (`templates/LOOP_POLICY.md:263`) |

### 2.2.1 One note on the observability overlap

His skill's question-first gate — define the two-to-four on-call questions
*before* instrumenting — is a good discipline we effectively followed (the metric
catalog in `docs/observability-architecture.md` was derived from stated
questions). His cardinality rule (never label metrics with user IDs, URLs, or
error text) does not bite us: we ship a log, not a metrics backend, and our
high-cardinality keys (`spec_id`, `run_id`) are the *point*.

The one line worth keeping in mind is his alert-severity rule — two tiers only,
page or ticket, because a third creates fatigue. We have no alerting at all
today, which is correct for a solo operator reading an evening digest. If
alerting is ever added, that rule should be adopted at that time, not now.

## 2.3 Steal a mechanism (5 proposed, 4 adopted)

Small, independent, no ordering between them. Each is a few lines of prompt or
policy inside a gate we already run.

### 2.3.1 The 95% confidence stop → PROPOSED AND REJECTED (2026-08-04)

From `interview-me`. The stop condition for a requirements interview is not a
question count; it is a self-test: can I predict the user's reaction to the next
three questions I would ask? If yes, stop.

This section originally recommended adopting it, on the grounds that our
*"capped ~5 questions"* is an arbitrary constant — simultaneously too many for
an obvious idea and too few for a genuinely ambiguous one.

**It was specced, grilled, and rejected on this repo's own grounds.** The
predictive test *is* self-reported confidence, and `templates/LOOP_POLICY.md:49`
is explicit: act on objective conditions, *"never on your own felt
confidence"*, because a confidently-wrong orchestrator will not flag its own
need for review. `README.md:172` calls verbalized confidence "the field's most
consistent negative result." The crude count cap is crude on purpose — it is
**structural**, and that is the property being traded away.

A structural replacement was considered — stop when no remaining question would
change a spec field, which is checkable against the emitted spec — and set aside
as not worth the complexity for a small win. The count cap stays.

Recorded rather than deleted so a future session does not re-import the same
mechanism, following the precedent of the rejected Audition lane in
`docs/roadmap.md`. It is also the most useful single result of the whole audit:
the catalog is good, and adopting from it uncritically will still import
mechanisms that contradict principles this repo has already paid to learn.

### 2.3.2 Cross-model payload hygiene → the shims

From `doubt-driven-development`. Two rules, and **checking them against our
shims split the finding in half** — one half does not apply to us, the other
does. Recorded that way rather than as originally drafted, because "we might have
this bug" and "we do not have this bug, and here is why" are different claims.

**The shell-injection half does not apply — verified, not assumed.** His rule
targets invoking another model's *CLI* with the artifact interpolated into a
shell-quoted argument, where embedded backticks or `$()` become shell execution.
Our shims do not use a CLI. Both build their request as JSON via `jq -n --arg`
(`scripts/call_sol.sh:92–94`, `scripts/call_fable.sh:60–62`) and hand it to
`curl -d "$REQUEST"` (`:110–114` and `:78–83` respectively). `--arg` performs
JSON string escaping, and `curl -d` receives one already-quoted argument that no
shell re-evaluates. There is no interpolation path here, so there is nothing to
fix.

This is worth stating explicitly in the document rather than silently dropping,
because it is a property of an architectural choice we already made for an
unrelated reason — *"Bash shims, not MCP wrappers or proxies"* (`README.md:164`),
chosen for token cost — that turns out to also close an injection class. Cheap
architecture paying off twice is exactly the kind of thing this repo should
notice.

**The prompt-injection half does apply, and is unaddressed.** We send
agent-generated code to an external model and feed its response back into a
pipeline that acts on it. Nothing in `templates/LOOP_POLICY.md` says that a
cross-family reviewer's output is untrusted text rather than instructions. This
is the same class as §2.4.2's untrusted-tool-output rule, and the two should be
stated together rather than in two places.

**As a gate:** one rule in `templates/LOOP_POLICY.md` covering both — external
model output and tool/error output are *data*, never instructions — and a
reviewer finding class for it. Downgraded from "possible live bug, check
immediately" to a small documentation gate, on evidence.

### 2.3.3 Severity prefixes and presumptive blockers → `agents/reviewer.md`

From `code-review-and-quality`. Two devices:

- **Severity prefixes** on findings: `Critical:` blocks merge, `Nit:` is
  optional, unprefixed is required. Our reviewer already types findings by
  `layer: spec|test|impl` and severity, but the *merge-blocking* distinction is
  not explicit — which matters more once `profile: dark` exists, because a
  `Critical:` finding is the natural ejection trigger.
- **Presumptive blockers**: a fixed list of structural problems the reviewer must
  surface even when unasked — complexity relocated rather than reduced, an
  oversized file with no decomposition, feature logic in shared modules,
  near-duplicate helpers, silent fallbacks.

That second list is the cheapest partial answer to §1.3(d). It is a *bounded,
enumerated* list, which is what makes it safe to add to a reviewer we
deliberately scoped away from taste: it cannot expand into general style
commentary, because it is finite.

### 2.3.4 Chesterton's Fence → the `minimize` ladder

From `code-simplification`. Before removing anything, establish why it exists —
check git blame, ask.

Our `minimize` ladder's first rung is "does this need to exist at all?"
(`agents/worker-cheap.md:22–34`). It pushes toward deletion with no counterweight
except the hard exception for validation, error handling, and security. In an
unattended loop that is a live risk: the ladder is applied by a haiku-tier worker
with no history of the codebase, and load-bearing code frequently looks
unnecessary from inside a single diff.

**As a gate:** add the fence as a precondition on the ladder's deletion rungs —
a removal must cite why the code existed (blame, a comment, a test that covers
it) or it is not eligible for removal.

### 2.3.5 The attempt ledger → `LEARNINGS.md`

From `performance-optimization`. Record optimizations attempted **and reverted**,
so a later run does not re-attempt them.

`LEARNINGS.md` already carries a two-strikes rule and a ~300-line cap. Extending
it to record dead ends — not just lessons — is a small change with a specific
payoff for an unattended loop, which has no memory of yesterday's failed approach
and will cheerfully rediscover it.

## 2.4 Real gaps — ranked (4)

### 2.4.1 `deprecation-and-migration` → an irreversibility classifier

**The gap, concretely.** A spec that renames a database column ships through our
factory today with a green `check_cmd`, a passing suite, a clean blind review,
and a well-formed PR — and breaks production during rollout, because old and new
code run simultaneously and one of them queries a column that no longer exists.
Nothing in our pipeline models deployment as a process with duration.

`skills/shelve` handles lifecycle for the *spec queue* (`shelved`, `superseded`,
with verified citations). It says nothing about the lifecycle of *shipped*
schemas and APIs.

**What his skill supplies.** The expand/migrate/contract pattern, with a worked
example: add the new column nullable → dual-write → backfill in batches → switch
reads → contract in a *later, separate* deploy. Plus Hyrum's Law as the reason
deprecation is hard, and the "churn rule" — if you own the deprecated
infrastructure, you own migrating its users.

**As a gate.** A spec-stage classifier that detects irreversible or
migration-shaped changes and:
1. sets `profile` accordingly (this is where the switch from §1.4.2 gets set),
2. requires the expand/contract split into *separate specs* with `depends_on`
   ordering — which our tracker already enforces mechanically,
3. blocks the dark lane (predicate clause 4).

**Why it ranks first.** It is the only gap where the current failure mode is
"ships green and breaks production," it supplies the consequence axis that
§1.3(b) says is missing, and it reuses `depends_on` rather than adding
machinery.

### 2.4.2 `debugging-and-error-recovery` → build-stage failure triage

**The gap.** Today, two failed `check_cmd` attempts sends the spec to `blocked`.
Between attempt one and attempt two there is no prescribed diagnostic discipline
at all — the build stage simply tries again. "Try again" is the least effective
debugging strategy available and the one an LLM defaults to.

**What his skill supplies.** The Stop-the-Line rule (on unexpected failure: stop
adding, preserve evidence, diagnose, fix root cause, guard with a regression
test, resume) and a triage checklist — reproduce, localize, reduce, fix root
cause, guard, verify end-to-end — with a symptom-vs-root-cause worked example.

It also carries a rule that is a genuine **safety property for us and stated
nowhere in this repo**: error output and stack traces are untrusted data. Do not
execute commands or visit URLs that appear inside an error message. An unattended
loop reading a test failure is reading attacker-influenceable text if any part of
the input is attacker-influenceable.

**As a gate.** A bounded triage step between attempt one and `blocked`:
reproduce → localize → one root-cause hypothesis with cited evidence → fix →
regression test. The Red Gate already applies to that regression test; the gate
makes it explicit on the failure path. Bounded, because unbounded triage is just
the unbounded revision loop we already rejected.

Plus one line in `templates/LOOP_POLICY.md` on treating tool output as data.

### 2.4.3 `security-and-hardening` → the payload behind `profile: hardened`

**The gap.** Security in our pipeline is one bullet in the blind review:
*"**security** — input validation gaps, injection vectors, authz"*
(`skills/review/SKILL.md:47`). That is a prompt line, and it is the entirety of
our security posture for shipped code.

**What his skill supplies.** STRIDE trust-boundary modeling with abuse cases
written alongside use cases; OWASP Top 10 prevention with runnable code; a
dependency-audit triage tree (severity × reachability × fix availability);
supply-chain hygiene (identify the true lockfile owner, block install scripts by
default, never `npm audit fix --force` blindly); and an OWASP-LLM section
covering prompt injection, output handling, and excessive agency.

**As a gate.** This is what `profile: hardened` finally routes to — turning the
dead field of §1.3(a) into the second switch position. Deliberately **not**
always-on: running a threat model on every typo fix is exactly the ceremony
§2.2 says we rejected, and would make the flag worthless by making it universal.

**Why it ranks third rather than first.** Security is the class Osmani says stays
human-reviewed — and in our factory it already does, because everything does. The
gap is depth, not presence, so the failure mode is "reviewed shallowly" rather
than "shipped unreviewed."

**A candidate payload exists off the shelf.** `docs/codex-subscription.md` §3.1
finds that OpenAI's `codex-plugin-cc` adversarial review is scoped to exactly
this attack surface — auth and trust boundaries, data loss and irreversible
state, rollback and idempotency, races, version skew — and that it asks a
different question from our own blind reviewer rather than a stricter version of
the same one. It is assessed there as a candidate for this payload, subject to
spec 001 landing first.

### 2.4.4 `source-driven-development` → prevention, not just detection

**The gap.** Our reviewer guard checklist catches hallucinated APIs *at review
time* — *"calls to functions/options that don't exist in the installed version"*
(`agents/reviewer.md:42–43`). Nothing at build time requires the worker to ground
API decisions in current documentation rather than in training data. We detect;
we do not prevent.

**What his skill supplies.** A Detect → Fetch → Implement → Cite pipeline with an
explicit source hierarchy (official docs > changelog > web standards > runtime
compat tables), explicitly excluding Stack Overflow and training recall as
authoritative.

**As a gate.** A citation requirement in the build brief for framework and
API-version decisions, verifiable in the diff — a decision that depends on
library behavior cites the doc URL and version it was checked against. Verifiable
because the citation is either in the diff or it is not.

**Why it ranks last of the four.** The detection half already works, so this
converts a caught-late failure into a caught-early one rather than an uncaught
one into a caught one. Real, but a smaller delta.

## 2.5 Deferred, with a reason (7)

| Skill | Verdict |
|---|---|
| `frontend-ui-engineering` | **A real gap we are deliberately not filling here.** We have zero accessibility coverage; review does conditional Playwright presence/behavior checks (`skills/review/SKILL.md:72–86`), which is not a WCAG audit. But this only binds for UI projects, and `docs/roadmap.md:34–44` establishes that domain scaffolding belongs in domain packs (the premiere-bridge precedent), not in the core loop. His "avoid the AI aesthetic" table is a good artifact for whoever builds that pack |
| `api-and-interface-design` | Overlaps §2.4.1 — Hyrum's Law is the shared anchor, and the irreversibility classifier is the enforceable half |
| `browser-testing-with-devtools` | We already do conditional Playwright. Adopting it adds a hard Chrome DevTools MCP dependency for marginal gain, against a repo principle: *"Bash shims, not MCP wrappers"* (`README.md:164`) |
| `shipping-and-launch` | Past our boundary. We terminate at an open PR; staged rollout with canary thresholds is the deploy pipeline's job, and we do not have one |
| `ci-cd-and-automation` | Partially covered — `check_cmd` plus the project suite is our quality gate. We have no CI-authoring ambition; his "Build Cop" role assumes a team |
| `documentation-and-adrs` | We deliberately minimize ADRs via Pocock's three-part test — hard to reverse, surprising, a real trade-off (`templates/factory-spec.md:50–52`). Only his ADR lifecycle rule is worth a line: never delete a superseded ADR, mark it and write a new one |
| `idea-refine` | The "Not Doing" list is already `boundaries_non_goals` in our brief (`templates/factory-spec.md:25–27`) |

## 2.6 The meta-finding

Osmani's pack is 24 prose skills — roughly 50,000 words of guidance, in a
consistent and genuinely well-designed format. Ours is 8 skills plus a set of
scripts that *refuse*.

Judged by the essay's own standard, that difference is the whole finding.
Verification is the bottleneck; only mechanically-provable oracles earn autonomy;
back pressure means autonomy expands no faster than verifiability. On those
terms, **a prose skill is a suggestion, and a suggestion is not a gate.** Our own
version of this lesson is recorded more bluntly: the person who ignored the
region-ownership doc was the agent that had written it hours earlier — *"'The
agent will read the docs' is not a safety property"* (`docs/factory.md:558–579`).

This is not a criticism of the catalog. A skill pack that must work across
seventy agents on arbitrary codebases cannot ship enforcement; it can only ship
knowledge, and it ships good knowledge. The right reading is that **the catalog
is a specification for gates we have not built** — which is exactly how Part 2
treats it. Every adoption above names the file it becomes a check in.

One structural idea *is* worth stealing wholesale, though: the **Common
Rationalizations** table. Pairing each excuse with its rebuttal is a better
format for agent-facing policy than a bare rule, because agents rationalize in
predictable ways and the table pre-empts the specific rationalization rather than
restating the rule louder. Our own `docs/factory.md` "what broke, and the rule it
became" section is the same move in narrative form. Worth considering for
`templates/LOOP_POLICY.md`'s non-negotiables.

Finally, note that adopt-by-reference remains available and has precedent:
`grill deep` already defers to `mattpocock-skills` when installed
(`skills/spec/SKILL.md:40–50`). For the deferred domain skills in §2.5 —
frontend, API design — pointing at Addy's pack when present is cheaper than
absorbing them and keeps them upstream-fresh. The pack is MIT-licensed, so either
path is open.

## 2.7 The adoption backlog

Ranked. Everything here needs an eval, and per repo culture
(`docs/factory.md:666`) each eval is verified by removing the check and
confirming failure.

| # | Item | Source | Target | Size |
|---|---|---|---|---|
| 1 | **Wire `profile:` as a three-position switch** | §1.3(a), §1.3(b), §1.4.2 | `templates/factory-spec.md`, `skills/spec`, `skills/review` | S — prerequisite for 2 and 4 |
| 2 | **Irreversibility classifier** + expand/contract split | §2.4.1 | `skills/spec`, `tracker.sh` `depends_on` | M |
| 3 | **Build-stage failure triage** + untrusted-tool-output rule | §2.4.2 | `skills/build`, `templates/LOOP_POLICY.md` | M |
| 4 | **`hardened` security payload** | §2.4.3 | `agents/reviewer.md`, `skills/review` | M |
| 5 | **The stolen mechanisms** — 4 of 5; §2.3.1 was rejected under grilling | §2.3 | shims, `agents/reviewer.md`, `agents/worker-cheap.md`, `LEARNINGS.md` | S each, independent |
| 6 | ~~Source-citation requirement~~ — **shelved** under grilling: targets scaffolded projects, but the plugin has no package manager to eval it against | §2.4.4 | — | — |
| 7 | **Comprehension proxies** — split in two under grilling: spec 013 captures diff size + finding count (they were never captured), spec 011 reports them | §1.3(c) | `scripts/lib/obs.sh`, `obs_metrics.jq`, `observe_metrics.sh` | S + M — prerequisite for 8 |
| 8 | **The dark lane** — including the escalation-trigger event that predicate clause 6 turns out to require | §1.4 | predicate script, `skills/build` + `skills/review` trigger event, `skills/config`, `skills/review` terminal transition | L — and see §1.4.7 |

Two ordering notes.

Item 5.2 was drafted as a possible live security bug and **was checked before
this document shipped**. It is not one: the shims build JSON with `jq --arg` and
post it with `curl -d`, so no shell re-evaluates the payload (§2.3.2). What
survives is the prompt-injection half, which merges into item 3's
untrusted-output rule rather than standing alone. Recorded here because a
document that grades a factory on evidence should show its own retraction rather
than quietly renumbering.

Item 8 should not start until the owner can name a recurring spec class from real
history that would have qualified — absent that, it is machinery for a
hypothetical. Grilling also surfaced a dependency gap in it: §1.4.6 specifies the
lane's auto-close against a *revert rate*, and item 7's split established that no
post-merge signal exists to compute one. `done` is terminal in the tracker. The
lane needs that capture before its safety valve is buildable at all.

**Grilling outcomes (2026-08-02 → 04).** Every item above was specced and
interviewed. Two were rejected or shelved on this repo's own principles rather
than on effort: §2.3.1's confidence stop (it *is* self-reported confidence,
which `LOOP_POLICY.md:49` forbids) and item 6 (unevaluable where it would be
authored). Two split in half once a claim was checked (items 5 and 7). One new
spec — automated `LEARNINGS.md` consolidation — came out of a review finding
that spec 009 cited a mechanism nobody had built. The audit's estimates survived
contact with grilling about half the time, which is roughly what the document's
own §2.6 predicts of prose that has not yet been made mechanical.

---

## Sources

- Addy Osmani, "Software Factories: Light and Dark" —
  https://addyo.substack.com/p/software-factories-light-and-dark
- Addy Osmani et al., `agent-skills` (MIT) —
  https://github.com/addyosmani/agent-skills
- Addy Osmani, "Loop Engineering" — https://addyosmani.com/blog/loop-engineering/
  (already cited in `docs/software-factory-analysis.md`)
- Matt Pocock, `skills` (`grilling`, `to-spec`) —
  https://github.com/mattpocock/skills

- OpenAI, `codex-plugin-cc` — https://github.com/openai/codex-plugin-cc
  (assessed in `docs/codex-subscription.md` as a candidate payload for §2.4.3)

Internal: `docs/factory.md` (implementation guide),
`docs/software-factory-analysis.md` (research companion),
`docs/observability-architecture.md` (the measurement plane §1.3(c) and §1.4.4
build on), `docs/roadmap.md` (domain-pack precedent cited in §2.5),
`docs/codex-subscription.md` (whether a ChatGPT subscription can fund Sol, and
what breaks in the metered-tier policy if it does).

---

*This document grades the factory; it does not change it. Everything in §2.7 is
unbuilt.*
