---
name: project_comprehension_json_no_proxy_label
description: spec 011 comprehension mode's default JSON rendering never labels the numbers as proxies, only --format tsv does — acceptance 3 says "any rendering"
metadata:
  type: project
---

Spec 011 (`factory/specs/011-comprehension-metrics.md`) acceptance 3: "Given
any rendering of these metrics, when it is read, then it names them as
proxies for comprehension debt." The implementation only prints the
`# PROXIES for comprehension debt` comment lines inside the `--format tsv`
branch of `scripts/observe_metrics.sh` (case `comprehension)` around line
131-134). The default format is `json` (`FORMAT="json"` at
`observe_metrics.sh:43`), and that branch (`printf '%s\n' "$RESULT"`) emits
the raw jq array with zero mention of "proxy" anywhere.

Confirmed live: `./scripts/observe_metrics.sh comprehension | grep -ci
proxy` → `0` on the default (json) format. `evals/cases/comprehension/802-*`
only exercises `--format tsv`, so this default-format gap is untested and
unnoticed by the suite.

**Why:** acceptance 3 exists specifically to prevent these weak proxies from
being mistaken for a real comprehension measurement (see spec Notes section)
— the gap defeats that purpose for anyone consuming the default/json output
(e.g. piping into another tool, which is exactly what most of this spec's
own eval cases do).

**How to apply:** on any future observe_metrics.sh mode with an
"acceptance: label X in any rendering"-style requirement, check BOTH the tsv
and the default json path, not just the format the eval case happens to
pick.
