---
name: project-codex-subscription-doc-citation-drift
description: docs/codex-subscription.md has a recurring pattern of prose claims (ratios, cross-refs, embellished citations) drifting from the tables/lines they cite, even when the tables themselves check out
metadata:
  type: project
---

`docs/codex-subscription.md` is under active, section-by-section review (§7
added on top of an already-reviewed §1–§6). Two independent reviews now found
the same defect class: the underlying data (tables, `file:line` citations) is
usually accurate, but **prose built on top of that data drifts** — a ratio
computed from rounded display values instead of the exact figures, a `§6
item N` cross-reference pointing at the wrong row, a citation that supports
only part of the sentence it's attached to.

Confirmed instances (2026-08-07 review of §7):
- §7.5 line 513 says "`§6 item 5` proposes it as the `hardened` payload" —
  item 5 in the §6 table (line 350) is the quota re-grounding item; the
  hardened-payload proposal is item 9 (line 354).
- §7.2's "DeepSeek V4 Flash 49×" (line 454) cheaper claim reproduces only by
  dividing the table's *rounded* display costs ($0.245/$0.005); the actual
  ratio from unrounded lean costs is ~53×. The other four ratios in the same
  sentence (8.5×, 3.3×, 17×, 6×) all check out against the unrounded costs,
  making the 49× figure an outlier, not the method.
- §7.1 line 421 cites `templates/LOOP_POLICY.md:202` for "the terminal state
  is an open PR reviewed in the morning" — line 202 only says "Terminal
  state is an open PR, never a merge"; "reviewed in the morning" is not
  sourced anywhere in that file.

An earlier review (referenced in this review's own task spec) separately
found a citation covering only part of its claim and two off-by-N line
numbers in an earlier pass over the same document.

Confirmed instances (2026-08-07 review of new §7.6 + §8, on top of an
already-reviewed §1–§7.5 — the §7.5 item-9 and DeepSeek-53× fixes above had
already landed by this pass):
- The drift pattern now extends to **raw input data**, not just prose built
  on top of it: §7.2's `z-ai/glm-5.2` row (line 451) and §7.6's copy of it
  (line 578) both give $0.76/$2.42 per M, but the live OpenRouter catalog
  (`curl -sS https://openrouter.ai/api/v1/models`, checked twice) returns
  $0.5026/$1.5796 for that exact id — every other priced row in both tables
  matched the live catalog exactly. Because GLM-5.2 is the document's
  headline cheap pick, this one stale number cascades into the "8.5×
  cheaper than Sol" ratio (true ~13×) and into §8.2's implementation/review
  cost-per-task and per-$30 figures (true ~$0.039/768 and ~$0.019/1588, not
  $0.059/504 and $0.029/1046) — all of which are otherwise *internally*
  consistent (i.e. correctly computed from the wrong input), so the error is
  invisible unless you re-fetch the catalog rather than just re-deriving
  from the table.
- §7.6 line 580 gives `qwen/qwen3.7-max` a "SWE-bench Verified 80.4" entry
  in the "Verified coding signal" column with no vendor/third-party
  qualifier — unlike the sibling DeepSeek-v4-pro row on the same line range
  which explicitly says "(third-party tracker)" — contradicting the
  document's own Sources-section claim that "every figure ... is labelled
  vendor-reported or third-party in §7.6."
- §7.6 line 601 claims Qwen 3.8 Max at $2.00/$6.00 "is the second-most-
  expensive option here," but Kimi K3 in the same table is $3.00/$15.00
  (line 574) — Qwen 3.8 Max is at best tied-third.
- §8.2's "High" confidence on the GLM-5.2 implementation pick (line 655,
  661) adds "verified on blind votes" — a methodology detail stated in the
  source table only for Kimi K3's row (line 574, "1,679 Elo / 483,895 blind
  votes"), not for GLM-5.2's row (line 578, which has no vote/Elo figure).

**Why:** the doc's authoring process apparently re-derives narrative
sentences from tables/citations by eye rather than recomputing/re-grepping
each time a new paragraph references them, so drift accumulates each time a
new section is appended.

**How to apply:** when reviewing further additions to this document (or
similar owner-authored analysis docs in this repo with dense
table+citation+backlog cross-referencing), always (a) recompute ratios from
the underlying unrounded numbers, never from the table's rounded display
cells, (b) re-grep every `§N item M` / `fileX:line` citation against the
actual current section/table, even when it looks superficially plausible,
and (c) — new as of the §7.6/§8 pass — re-fetch any live external price/data
source rather than trusting a table's stated $/M figures, since a single
stale input row (not just a derived sentence) can now be the drift source
and silently poisons every downstream cost table that reuses it. The
tables/base data used to be reliably correct; that is no longer a safe
assumption for prices claimed to be "live."
