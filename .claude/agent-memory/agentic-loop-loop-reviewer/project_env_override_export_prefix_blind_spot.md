---
name: project_env_override_export_prefix_blind_spot
description: doctor.sh's grep-based .env override lookups don't match `export VAR=value` lines even though common.sh's `source ./.env` (the real resolution path) does — confirmed on spec 019's alias-liveness check
metadata:
  type: project
---

Spec 019 (`openrouter-alias-liveness`) added a check in `scripts/doctor.sh`
that resolves an alias's `.env` override with:
`grep -m1 "^${OR_VAR}=" ./.env | cut -d= -f2- | tr -d '"'"'"''`
(doctor.sh:119). This requires the line to start with the bare var name.
The real resolution path — `scripts/lib/common.sh` sourcing `./.env`
(used by `call_openrouter.sh` and doctor's own worker-key section further
down at doctor.sh:146, `set -a; source ./.env; set +a`) — handles
`export VAR=value` lines fine, since `source` is real bash.

**Confirmed live:** with `.env` containing
`export OPENROUTER_MODEL_KIMI=totally-dead-vendor/does-not-exist`,
`call_openrouter.sh --model kimi` correctly resolves the dead override
and would fail/refuse on a real call, but `doctor.sh`'s alias-liveness
block silently falls back to the built-in default and reports
`[ok] alias 'kimi' -> moonshotai/kimi-k3 is in the OpenRouter catalog` —
completely missing the actual override in use. This is a direct
violation of spec 019 acceptance 2's own stated rule: "checking the
built-in default while the project uses something else would report on
a value nobody calls." No eval case in `evals/cases/alias-liveness/`
uses an `export`-prefixed `.env` line, so nothing caught it.

Note: this same grep-based pattern pre-exists for `OLLAMA_MODEL` at
doctor.sh:40 (not introduced by spec 019) — so it's a pattern already
established in this file, just never exercised against `export` syntax
before. `.env` files with CRLF line endings hit the identical bug in
BOTH the grep path and the real `source` path (both leave a trailing
`\r` in the value) — that one is a pre-existing common.sh-wide issue,
not specific to this check, and not worth re-flagging on its own.

**How to apply:** whenever a spec adds a second, independent `.env`
value-reading mechanism alongside the project's existing `source ./.env`
convention (usually because of a load-order constraint), test it against
`export VAR=value` — this project's `.env.example` never uses `export`,
but nothing stops a user from writing it that way, and grep-based reads
silently diverge from what `source` actually resolves.
