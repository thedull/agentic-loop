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
