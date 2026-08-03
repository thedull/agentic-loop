---
name: factory-spec-conventions
description: Structure and mechanics of factory/specs/*.md files in the agentic-loop repo, and how scripts/lib/tracker.sh actually enforces depends_on.
metadata:
  type: project
---

Specs live in `factory/specs/NNN-slug.md` with frontmatter (id, title, status,
profile, created, depends_on, claimed_by, branch, pr) and body sections:
Brief (6-field delegation contract: objective, user_intent_verbatim,
input_paths, boundaries_non_goals, output_spec, effort_budget), Acceptance
(RFC-2119 SHALL + Given/When/Then, meant to be one step from an executable
test), Check command (`check_cmd:` — a single command whose exit status is
the Red Gate), Notes (append-only, hard-to-reverse decisions only), Revision
log (deltas only, never regenerated).

`scripts/lib/tracker.sh` VALID_STATUSES: queued specd building built
reviewing pr-open blocked shelved superseded done. `depends_on` is satisfied
ONLY by a dependency spec whose status is `done`, or a `superseded` spec
whose `superseded_by` citation is verified to have landed on the default
branch (`_tracker_dep_met`, tracker.sh ~L224-233). `built`/`pr-open` never
satisfy a dependency — deliberate, per the header comment (~L27-36): unmerged
work isn't on main, so a dependent build could not see it.

`skills/spec/SKILL.md` spec-authoring is an interactive conversation
(one question at a time, capped ~5 for medium/large ideas; one confirmation
question for trivial/small). This is the only place a "human confirms
explicitly" pattern currently exists in the repo — relevant when a spec's
acceptance criteria assume human-in-the-loop override without naming a
mechanism.

Evals: `./evals/run_eval.sh --suite <name>` runs cases from
`evals/cases/<name>/`. Default (no `--live`) skips `headless-agent` kind
cases and treats skips as non-failing (exit 0 if nothing actually fails).
See [[project-spec-gate-checkcmd]] and [[feedback-run-checkcmd-dont-just-read-it]]
for the confirmed vacuous-check_cmd instance in this suite.
