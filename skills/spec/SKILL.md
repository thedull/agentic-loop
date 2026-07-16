---
name: spec
description: >-
  Turn an idea into a factory spec: triage its size, grill the user with
  one-question-at-a-time interrogation (adaptive depth), emit a single spec
  file with a machine-checkable done-condition, and gate it through a
  fresh-context spec review before it enters the build queue. Use when the
  user hands over an idea (or a list of ideas) for the factory to build
  unattended. Interactive — run it while the user is present.
---

# agentic-loop:spec — idea → reviewed spec

You are the spec stage of the factory. Your output is ONE file per idea in
`factory/specs/` (template: `templates/factory-spec.md` in the plugin root;
already copied to the project by init). Everything downstream runs unattended
— the questions you don't ask now become wrong guesses at build time, but
every question costs the user's morning. Adaptive depth resolves the tension.

Token discipline (non-negotiable): one spec file per idea — never generate
constitution/research/data-model/contract documents. Look up facts in the
repo yourself (grep/read); only DECISIONS go to the user. Never inline file
contents into the spec — paths only.

## Steps per idea

If the user gave a list of ideas, capture each as a file with `status: queued`
first (id from `scripts/lib/tracker.sh next-id`, one-line objective), then
process them one at a time through the steps below. Never interleave the
grilling of two ideas.

1. **Triage effort_budget FIRST** — cheap questions before deep ones: does it
   touch one seam or several? Is it easily reversible? Answer them yourself
   from the codebase where possible.
   - `trivial`/`small` (one seam, reversible): ask ONE confirmation question
     restating the idea + proposed check command, then emit the spec directly.
   - `medium`/`large` (multiple seams, hard-to-reverse, real trade-offs):
     full grilling, capped at ~5 user-facing questions (prefer informed,
     stated assumptions over a sixth question).

2. **Grill (when depth warrants)** — one question at a time; wait for each
   answer; never batch. Walk the decision tree, not a checklist: each answer
   determines the next question. Explore the relevant code BETWEEN questions
   so you never ask what you can read.

3. **Emit the spec** from the template:
   - the 6-field brief (user_intent_verbatim = their actual words, uncut);
   - acceptance as RFC-2119 SHALL + Given/When/Then, each one step from a test;
   - `check_cmd` — a single command whose exit status decides done-ness. If
     the acceptance references UI behavior and the project has a runnable web
     UI, note that so the review stage runs browser verification;
   - a Notes entry ONLY if a decision is hard-to-reverse + surprising +
     a real trade-off (1–3 sentences);
   - `profile: hardened` only if the user explicitly asked for
     correctness-critical treatment.

4. **Spec review gate** (skip for `trivial`) — delegate to the `loop-reviewer`
   subagent with ONLY the spec file path (blind, fresh context). Brief it to
   find: ambiguous language, missing edge cases, implicit assumptions,
   contradictions, and a `check_cmd` that could pass vacuously. Fix findings
   now — with the user if a finding needs a decision. This is the cheapest
   moment in the whole pipeline to fix a spec flaw.

5. **Advance**: `scripts/lib/tracker.sh advance <file> specd`, then tell the
   user the id, effort_budget, and check command, and move to the next idea.

## What NOT to do

- Do not start building. Building is the build stage's job.
- Do not regenerate a spec on later feedback — append deltas to its
  Revision log.
- Do not ask the user anything you can answer with grep.
