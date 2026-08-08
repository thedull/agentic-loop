---
name: primary-objective-unenforced-by-checkcmd
description: A spec's Brief-level primary objective can lack any Red Gate enforcement while a secondary/detector objective in the same spec is fully fixture-covered — check that check_cmd actually exercises every numbered acceptance, not just the ones with fixtures named in the Build-order note.
metadata:
  type: project
---

Spec 019's brief states two objectives: (1) "point the OpenRouter aliases at
the current generation" (acceptance 1) and (2) make a delisted id something
`doctor.sh` detects (acceptances 2-5). The "Build order" / "Fixtures needed"
section only names fixtures for objective 2 (catalog present/absent/
malformed/empty/timeout + override `.env`) — nothing enforces objective 1.

Confirmed live (`curl https://openrouter.ai/api/v1/models`, 2026-08-08): the
*current, unrefreshed* ids `moonshotai/kimi-k2` and `minimax/minimax-m2`
are both still present in the catalog (newer ids `kimi-k3` / `minimax-m3`
also exist). So a literal reading of acceptance 1 ("resolve to ids present in
the catalog") is satisfied by doing nothing — the check_cmd cannot
distinguish "refreshed to current-generation" from "left alone, coincidentally
still alive." "Current-generation" has no objective, mechanically-checkable
definition anywhere in the spec.

**Why:** the Red Gate is supposed to be the enforcement mechanism per this
project's factory convention — a spec whose primary stated objective has no
corresponding fixture/case is trusting the builder's judgment for the part
the process exists to remove judgment from.

**How to apply:** when reviewing a spec's acceptance list, map each
acceptance number to a concrete fixture/case in the Build-order note. If an
acceptance (especially the one mirroring the Brief's headline objective) has
no fixture and its pass condition is satisfiable by a no-op, flag it —
regardless of how well-specified the *other* acceptances are. 1st strike:
spec 019.

2nd strike: spec 004 (`factory/specs/004-eval-runner-zero-case-exit.md`)
acceptance 7's last bullet — "Consequence for build order, which the build
skill must state: the builder writes the suite and its cases FIRST..." — is a
required prose edit to `skills/build/SKILL.md` (listed in input_paths) that
distinguishes exit 4 ("nothing ran," Red Gate NOT satisfied) from exit 1
(genuine failure, Red Gate satisfied). The spec's own `check_cmd`
(`./evals/run_eval.sh --suite evalrunner`) can only exercise the runner's
exit-code behavior (acceptances 1-6); it cannot verify that
`skills/build/SKILL.md` was actually edited, or edited correctly, to make
this distinction. Confirmed live: the unmodified `skills/build/SKILL.md`
step 4 (lines 44-50) says only "Run check_cmd; it MUST fail. If it passes on
the untouched codebase, the check is vacuous" — generic nonzero-vs-zero
logic with no exit-4-vs-exit-1 branch, so a builder following it literally
would treat exit 4 as satisfying "it MUST fail." Pattern now confirmed
across two unrelated specs — treat as a standing check on every future spec
whose acceptance criteria include a process/doc change (not just a code
change): does check_cmd cover it, or is it trust-the-builder?

3rd strike: spec 009 (`factory/specs/009-attempt-ledger.md`). The Brief's
headline objective ("give the loop a memory of approaches that were tried
and abandoned") is realized by acceptances 3-4 ("stages consult the ledger
before proposing an approach" / "retrying is explicit"). The spec's own note
(lines 56-59) admits these "concern stage reasoning and belong on the
anchored-rubric or `--live` path," but `check_cmd` (line 45) is
`./evals/run_eval.sh --suite ledger` with no `--live`. Confirmed live:
`evals/run_eval.sh:89-91` skips `headless-agent` cases when not `--live`,
and `evals/README.md:25` states skips "never fail a run." So the spec
*names its own gap in prose* but still ships a check_cmd that can't reach
it — the self-awareness doesn't change the mechanical outcome. Treat
"the spec says these acceptances need --live" as itself a red flag unless
check_cmd includes --live or a separate always-run gate is named.

4th strike: spec 013 (`comprehension-capture`) acceptance 1 (diff size).
Unlike acceptance 2 (review-finding count), which can attach to the
`SubagentStop` hook — an automatic, always-fires CLI hook that bash-unit
fixtures can already exercise with a synthetic stdin payload (see
`evals/cases/observability/018`, `/020` — no live agent needed) — diff size
has no equivalent automatic hook. `hooks/hooks.json` registers only
SessionStart/SubagentStart/SubagentStop/SessionEnd; nothing fires "when a
diff exists." The only place a diff is computed is `skills/review/SKILL.md`
step 4 prose (`git diff main...claude/idea-<slug>`), executed by the live
orchestrating agent, not by any script under test. A check_cmd suite can
only prove that `scripts/observe.sh emit <event> <overlay>` plumbs arbitrary
fields through correctly — which the generic `emit` command already does,
unmodified — never that the review skill actually calls it. **Pattern
refinement: when a spec bundles two "new fields," check whether they share a
capture mechanism — a hook-backed field and a prose-only field can look
symmetric in the Brief while having very different Red Gate enforceability.**

5th strike: spec 001 (`profile-switch`). Acceptance 1 requires that an
invalid `profile:` value "marks the spec `blocked`". Acceptance 3 requires
"the review stage SHALL route `hardened` specs through the deeper review
path". Neither is implemented: the diff only adds a `tracker.sh profile`
library primitive plus a skip-not-block branch inside `tracker_claim`
(scripts/lib/tracker.sh:319-328) — nothing ever calls `_tracker_set_field
... status blocked` for a bad profile (confirmed live: claiming a
`profile: banana` spec leaves `status: specd` unchanged, never `blocked`).
And `skills/review/SKILL.md` / `skills/build/SKILL.md` — both named in the
spec's own `input_paths` — have zero mentions of "profile" (`grep -c
profile` = 0 in both), so there is no "review stage" that actually routes
hardened through anything; the primitive is only ever called from the claim
gate. `check_cmd` (`--suite profile`) only exercises the primitive directly
against fixtures, so it cannot catch either gap — same shape as strike 4:
a Brief-level acceptance with no hook into any real stage, invisible to a
suite built purely around the primitive's own fixtures.
