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

const MAX_IDEAS = (args && args.maxIdeas) || 2

phase('Scout')
const scout = await agent(
  `You are the factory scout. Steps:
   1. Run: scripts/lib/usage_gate.sh check
      - exit 5 (postpone): append "factory postponed until <resets_at as local time>" to .agentic/STATUS.md and return {"gate":"postpone","specs":[]}.
      - exit 0: continue (a fail-open warning on stderr is fine).
   2. Run: scripts/lib/tracker.sh list specd
   3. Return the gate verdict and up to ${MAX_IDEAS} spec file paths, oldest first.`,
  {
    label: 'scout',
    model: 'haiku',
    effort: 'low',
    schema: {
      type: 'object',
      properties: {
        gate: { type: 'string', enum: ['proceed', 'postpone'] },
        specs: { type: 'array', items: { type: 'string' } },
      },
      required: ['gate', 'specs'],
    },
  }
)

if (!scout || scout.gate === 'postpone' || scout.specs.length === 0) {
  return { ran: 0, reason: scout ? scout.gate === 'postpone' ? 'usage gate' : 'queue empty' : 'scout failed' }
}

log(`Queue: ${scout.specs.length} spec(s), cap ${MAX_IDEAS}`)

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

const results = await pipeline(
  scout.specs,
  (specPath) =>
    agent(
      `Execute the factory BUILD stage for exactly one spec: ${specPath}.
       Follow the procedure in the agentic-loop plugin skill "build"
       (skills/build/SKILL.md) to the letter: claim specd->building via
       scripts/lib/tracker.sh, isolated worktree + branch, Red Gate
       (check_cmd must FAIL before implementation), tier-routed build per the
       project CLAUDE.md, check_cmd green + project suite, commit, advance to
       built (or blocked with reasons recorded). Do NOT push or open a PR.
       Return the final tracker status for this spec.`,
      { label: `build:${specPath}`, phase: 'Build', model: 'sonnet', effort: 'medium', schema: STAGE_SCHEMA }
    ),
  (buildResult, specPath) => {
    if (!buildResult || buildResult.status !== 'built') {
      log(`skip review for ${specPath}: build ended '${buildResult ? buildResult.status : 'failed'}'`)
      return buildResult
    }
    return agent(
      `Execute the factory REVIEW stage for exactly one spec: ${specPath}
       (branch ${buildResult.branch}). Follow the procedure in the
       agentic-loop plugin skill "review" (skills/review/SKILL.md) to the
       letter: claim built->reviewing, blind fresh-context review of spec +
       diff only, findings typed layer:spec|test|impl, bounded revision (hard
       cap 2), conditional browser verification, push branch + open PR,
       advance to pr-open, append the digest entry to .agentic/STATUS.md.
       Never merge; never call metered tiers — record needs_escalation
       instead. Return the final tracker status and PR reference.`,
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
