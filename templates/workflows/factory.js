// Factory workflow — single-session, serial-per-idea composition of the
// build and review stages. This is the recommended day mode: one session,
// `/loop 60m` re-invoking this workflow, cheapest per idea.
//
// Save to .claude/workflows/factory.js (project) to run as /factory.
// Optional args: {"maxIdeas": 3}  — hard cap per run (default 2).
//
// Design notes:
// - Workflow scripts have no filesystem access, so a scout agent (haiku)
//   enumerates the queue and checks the usage gate; stage agents execute the
//   skill procedures. Skills' own rules still bind the agents: Red Gate,
//   envelope validation, no metered tiers unattended, blocked-over-guessed.
// - pipeline() runs each idea through build→review independently; idea B
//   builds while idea A reviews. Worktree isolation (in the skill procedure)
//   keeps parallel stages from colliding.
// - Tiering: scout=haiku/low; build+review=sonnet/medium (they delegate
//   mechanical parts down per the routing CLAUDE.md). The main session model
//   is deliberately NOT inherited — the factory must not burn frontier quota.

export const meta = {
  name: 'factory',
  description: 'Drain the factory spec queue: build then review each specd idea, one PR per idea',
  whenToUse: 'Day-mode unattended run over factory/specs/ after /agentic-loop:spec filled the queue',
  phases: [
    { title: 'Scout', detail: 'usage gate + queue listing' },
    { title: 'Build', detail: 'one branch per spec, Red Gate discipline' },
    { title: 'Review', detail: 'blind review, bounded revision, PR + digest' },
  ],
}

// ---------------------------------------------------------------------------
// This file is YOURS. Edit it freely — sequencing, extra stages, tiering.
//
// The spans marked `owner=plugin` below are the exception: they carry the
// safety policy and stage contracts, and `/agentic-loop:update` refreshes them
// in place so improvements reach you. Everything outside those markers is
// project-owned and is never touched by an update.
//
// To customize a stage, DON'T edit inside a plugin region — a hand-edit there
// is detected and refused (it is how a project once silently dropped the
// "record needs_escalation" rule). Add to the project addendum constants
// instead; they are appended to the plugin's prompt.
// ---------------------------------------------------------------------------

// Yours to tune (1 = strictly serial). Keep the NAME: the plugin's scout
// region interpolates it, so renaming it breaks a region you cannot edit.
const MAX_IDEAS = (args && args.maxIdeas) || 2

// Project-owned: extra instructions appended to each stage's prompt. Machine
// realities go here — ports that must stay up, fixture env vars, package
// manager quirks. Keep them factual; policy lives in the plugin regions.
const PROJECT_BUILD_ADDENDUM = ''
const PROJECT_REVIEW_ADDENDUM = ''

phase('Scout')
// @agentic-loop:begin region=scout-prompt owner=plugin
const SCOUT_PROMPT =
  `You are the factory scout. Steps:
   1. Run: scripts/lib/usage_gate.sh check
      - exit 5 (postpone): append "factory postponed until <resets_at as local time>" to .agentic/STATUS.md and return {"gate":"postpone","specs":[]}.
      - exit 0: continue (a fail-open warning on stderr is fine).
   2. Run: scripts/lib/bench.sh reconcile
      - no-op unless .bench.enabled is set in .agentic/config.json; otherwise
        ensures every pr-open spec has a fresh review bench and removes
        benches for specs that have left the queue (done, shelved,
        superseded). Never fails this step either way.
   3. Run: scripts/lib/tracker.sh list specd
   4. Return the gate verdict and up to ${MAX_IDEAS} spec file paths, oldest first.
      Specs waiting on unmet depends_on are not claimable — tracker.sh skips
      them itself; never work around that gate.`
const SCOUT_SCHEMA = {
  type: 'object',
  properties: {
    gate: { type: 'string', enum: ['proceed', 'postpone'] },
    specs: { type: 'array', items: { type: 'string' } },
  },
  required: ['gate', 'specs'],
}
// @agentic-loop:end region=scout-prompt

const scout = await agent(SCOUT_PROMPT, {
  label: 'scout',
  model: 'haiku',
  effort: 'low',
  schema: SCOUT_SCHEMA,
})

if (!scout || scout.gate === 'postpone' || scout.specs.length === 0) {
  return { ran: 0, reason: scout ? scout.gate === 'postpone' ? 'usage gate' : 'queue empty' : 'scout failed' }
}

log(`Queue: ${scout.specs.length} spec(s), cap ${MAX_IDEAS}`)

// @agentic-loop:begin region=stage-schema owner=plugin after=scout-prompt
const STAGE_SCHEMA = {
  type: 'object',
  properties: {
    spec: { type: 'string' },
    status: { type: 'string' },
    branch: { type: 'string' },
    pr: { type: 'string' },
    summary: { type: 'string' },
    caveats: { type: 'array', items: { type: 'string' } },
  },
  required: ['spec', 'status', 'summary'],
}
// @agentic-loop:end region=stage-schema

// @agentic-loop:begin region=build-prompt owner=plugin after=stage-schema
const BUILD_PROMPT = (specPath) =>
  `Execute the factory BUILD stage for exactly one spec: ${specPath}.
   Follow the procedure in the agentic-loop plugin skill "build"
   (skills/build/SKILL.md) to the letter: claim specd->building via
   scripts/lib/tracker.sh, isolated worktree + branch, Red Gate
   (check_cmd must FAIL before implementation), tier-routed build per the
   project CLAUDE.md, check_cmd green + project suite, commit, advance to
   built (or blocked with reasons recorded). Do NOT push or open a PR.
   Return the final tracker status for this spec.`
// @agentic-loop:end region=build-prompt

// @agentic-loop:begin region=review-prompt owner=plugin after=build-prompt
const REVIEW_PROMPT = (specPath, branch) =>
  `Execute the factory REVIEW stage for exactly one spec: ${specPath}
   (branch ${branch}). Follow the procedure in the agentic-loop plugin skill
   "review" (skills/review/SKILL.md) to the letter: claim built->reviewing,
   blind fresh-context review of spec + diff only, findings typed
   layer:spec|test|impl, bounded revision (hard cap 2), conditional browser
   verification, push branch + open a PR whose body includes the mandatory
   test plan (checkable steps + what could NOT be verified), advance to
   pr-open, append the digest entry to .agentic/STATUS.md.
   Never merge; never call metered tiers — record needs_escalation
   instead. Return the final tracker status and PR reference.`
// @agentic-loop:end region=review-prompt

const results = await pipeline(
  scout.specs,
  (specPath) =>
    agent(
      BUILD_PROMPT(specPath) + PROJECT_BUILD_ADDENDUM,
      { label: `build:${specPath}`, phase: 'Build', model: 'sonnet', effort: 'medium', schema: STAGE_SCHEMA }
    ),
  (buildResult, specPath) => {
    if (!buildResult || buildResult.status !== 'built') {
      log(`skip review for ${specPath}: build ended '${buildResult ? buildResult.status : 'failed'}'`)
      return buildResult
    }
    return agent(
      REVIEW_PROMPT(specPath, buildResult.branch) + PROJECT_REVIEW_ADDENDUM,
      { label: `review:${specPath}`, phase: 'Review', model: 'sonnet', effort: 'medium', schema: STAGE_SCHEMA }
    )
  }
)

const done = results.filter(Boolean)
return {
  ran: done.length,
  prOpen: done.filter((r) => r.status === 'pr-open').map((r) => ({ spec: r.spec, pr: r.pr || '' })),
  blocked: done.filter((r) => r.status === 'blocked').map((r) => ({ spec: r.spec, why: r.summary })),
}
