---
name: project-002-skill-not-wired-and-005-gap
description: spec 002 declared skills/spec/SKILL.md + templates/factory-spec.md in input_paths but never touched them, and its split output (profile hardened) is unclaimable today because spec 005's payload marker isn't installed and 002 doesn't depends_on 005.
metadata:
  type: project
---

Two related spec-002 gaps found on first review (branch
claude/idea-002-irreversibility-classifier):

1. **Workflow not wired.** input_paths named `skills/spec/SKILL.md` and
   `templates/factory-spec.md`, but `git diff main...claude/idea-002...`
   touches neither. skills/spec/SKILL.md step 5 still just says
   `tracker.sh advance <file> specd` with no mention of the classifier, the
   `split` command, or the override-line syntax an author would need to know
   about. An agent following the actual skill hits the new refusal with no
   documented next step.

2. **Split output is currently dead-ended.** `tracker.sh split` stamps
   `profile: hardened` on both halves (per acceptance 6), but spec 005
   (hardened review payload) is only `specd`, not built — `agents/` has no
   `profile-hardened-payload:` marker. Confirmed live: after splitting and
   advancing both halves to `specd`, `tracker.sh claim specd building`
   refuses BOTH — contract on depends_on (correct, acceptance 5 works), AND
   expand on profile (spec 001's hardened gate, exit 6 style). Spec 002's own
   `depends_on: 001 004` doesn't list 005, so nothing flags this sequencing
   gap.

**Why:** input_paths and depends_on are supposed to be the seams a spec
declares up front — see [[project_reopen_cycle_metric_aggregation_gap]] and
[[project_primary_objective_unenforced_by_checkcmd]] for the same class of
"declared but not delivered / not sequenced" gap in this repo's specs.

**How to apply:** when reviewing any spec whose acceptance depends on another
spec's payload existing (here: profile hardened depends on spec 005), check
whether depends_on actually lists it, not just whether the runtime code path
exists. And always diff every path in input_paths against what the branch
actually touched — an untouched declared input_path is a real finding, not
noise.
