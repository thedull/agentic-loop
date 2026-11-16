---
id: 020
title: Operate the factory against GitLab and other forges, not only GitHub
status: pr-open
profile: standard
created: 2026-11-16
claimed_by:
branch: claude/idea-forge-adapters
pr:
---

# Spec 020 — Operate the factory against GitLab and other forges, not only GitHub

## Brief (the delegation contract)

- **objective**: route every forge operation the factory performs (push, open a PR/MR, read its state, close it, check auth) through one seam, `scripts/lib/forge.sh`, with `github`, `gitlab` and `none` adapters.
- **user_intent_verbatim**: "Let's evolve agentic-loop itself to be able to operate with GitLab or other VCSs first" (2026-11-16). Owner rulings, same day:
  - detection: *"Declare it, no network guess"*;
  - reviewers: *"No OotB reviewer support. This should be done in a per-project basis on the AGENTS or CLAUDE.md files."*
- **input_paths**: `scripts/lib/forge.sh`, `scripts/lib/tracker.sh`, `skills/review/SKILL.md`, `skills/shelve/SKILL.md`, `skills/config/SKILL.md`, `skills/init/SKILL.md`, `templates/workflows/factory.js`, `templates/.env.example`, `scripts/doctor.sh`, `scripts/lib/scaffold.sh`, `docs/factory.md`, `README.md`, `evals/cases/forge/`, `evals/fixtures/`, `evals/run_eval.sh`, `.agentic/config.json`, `scripts/lib/obs.sh`
- **boundaries_non_goals**:
  - Does NOT assign reviewers, labels or assignees. Projects that want that do it in their own `CLAUDE.md`/`AGENTS.md` or through `PROJECT_REVIEW_ADDENDUM` in `.claude/workflows/factory.js`. This is the project-owned seam, and it already exists.
  - Does NOT merge anything. The terminal state stays an open PR/MR, and merging stays human.
  - Does NOT ship Gitea/Forgejo or Bitbucket adapters. It documents the adapter contract so one can be added without touching callers.
  - Does NOT probe the network to detect a forge.
  - Does NOT depend on `glab`. GitLab is reached through its REST API with `curl`, which is already a required tool in `scripts/doctor.sh`.
  - Does NOT rename the tracker status `pr-open`. Existing spec files, the observability metrics and the dashboards key on it.
  - Does NOT consolidate the three default-branch resolutions (`tracker.sh` ×2, `bench.sh`). They differ on purpose: `_tracker_supersede_lands` refuses the current-branch fallback that `tracker_reconcile_done` accepts. Unifying them is a separate decision with its own risk.
  - Does NOT replace the tracker's file backend. The issue-tracker connector seam is unrelated.
- **output_spec**:
  - A sourceable library and CLI, `scripts/lib/forge.sh`, offering `kind`, `remote`, `push`, `pr-create`, `pr-state`, `pr-close` and `check`.
  - Every forge call in a project scaffolded with it goes through `forge.sh`, `doctor.sh` included (via `check`). The one deliberate exception is acceptance 8's legacy fallback, which exists only for projects that predate this spec and so lack `forge.sh`.
  - The review stage opens PRs/MRs through it, the tracker's merged-state fallback reads through it, the shelve skill closes through it, and `doctor.sh` reports on it.
  - Projects receive it through the scaffold manifest.
- **effort_budget**: medium

## Acceptance (behavioral, testable — no implementation details)

1. `forge.sh kind` SHALL resolve the forge deterministically and without network access.
   - **Precedence:** given `FORGE` in the environment, when `kind` runs, then that value wins over `./.env`, over `.agentic/config.json` `.forge.kind`, and over auto-detection. Given none in the environment but `FORGE=` in `./.env`, then the `./.env` value wins over config and auto-detection.
   - **Matching:** host matching is case-insensitive and looks at the host only, never the path.
   - **github:** given no declaration and a remote URL whose host is `github.com` or `www.github.com` (https, `git@` or `ssh://` form), when `kind` runs, then it prints `github`.
   - **gitlab by name:** given no declaration and a remote host with any dot-separated label that **starts with** `gitlab` (e.g. `gitlab.example.test`, `GitLab-EE.corp.example.test`), when `kind` runs, then it prints `gitlab`.
   - **near misses:** given `notgitlab.example.test`, or a `github.com` remote whose path contains `gitlab`, then the `gitlab` rule does not match.
   - **unrecognised host:** given no declaration and a host matching neither rule, including a GitHub Enterprise host, when `kind` runs, then it prints `none` and exits 0. Such a host works once declared, e.g. `FORGE=github`.
   - **empty or unreadable declarations:** given `FORGE=` with an empty value (in the environment or `./.env`), then it counts as **not declared**, not as invalid. Given `.agentic/config.json` absent, unreadable or malformed, then it counts as no config, and resolution continues.
   - **no remote:** given no remote configured, when `kind` runs, then it prints `none`.
   - **invalid value:** given a declared value outside `github|gitlab|none`, when `kind` runs, then it exits non-zero, names the bad value on stderr, and prints nothing on stdout. An invalid value never falls back to a default.
   - **no network:** given any of the above, when `kind` runs, then no HTTP request is made. The forge mock seam records zero requests.
2. The remote the forge layer acts on SHALL be configurable and default to `origin`.
   - Given `FORGE_REMOTE`, or `.forge.remote` in `.agentic/config.json`, when `remote` runs, then it prints that name (env first). Given neither, then it prints `origin`.
   - **declaration vs a missing remote:** a declared kind wins over auto-detection, but no forge operation is possible without a remote. Given a configured remote name that does not exist in the repository, or no remote at all, when `kind` runs, then it prints the declared kind if there is one, else `none`.
   - **`push` without a remote:** given no usable remote (whatever the kind), when it runs, then it prints `no remote` on stderr, pushes nothing, and exits 0. It must not fail an unattended review that today simply skips the push.
   - **`pr-create` without a remote:** given the same, when it runs, then it prints `local` and exits 0.
3. `forge.sh pr-create --head B --base T --title S --body-file F` SHALL open exactly one PR/MR and print only its URL.
   - **project id:** the project id is the remote's repository path, with a trailing `.git` stripped, fully URL-encoded (subgroups included), for every remote form:
     - `https://host[:port]/group/sub/proj.git`;
     - scp-style `git@host:group/sub/proj.git`;
     - `ssh://git@host[:port]/group/sub/proj.git`.

     When `FORGE_URL` has a path prefix and an https remote path starts with it, the prefix is removed first.
   - **gitlab:** given kind `gitlab`, when it runs, then it issues one create request for that project id. The request carries source `B`, target `T`, title `S` and the description read from `F`. It prints the returned web URL as the only stdout line and exits 0.
   - **gitlab, existing MR:** given kind `gitlab` and an already-open MR for source `B`, when it runs, then it prints that MR's URL, creates no second one, and exits 0, so a re-run review stage is idempotent.
   - **github:** given kind `github`, when it runs, then it first looks up an open PR for head `B` (`gh pr view` or `gh pr list` on that head). If one exists, it prints that URL and exits 0, idempotent like the gitlab case. Otherwise it invokes `gh pr create` with the same head, base, title and body file, and prints the URL `gh` reports.
   - **none:** given kind `none`, when it runs, then it prints `local` and exits 0, which is today's no-remote behaviour. `local` is the **only** non-URL value `pr-create` may print.
   - **error:** given an API or `gh` failure, when it runs, then it exits non-zero, prints the HTTP status or `gh` error on stderr, and prints **nothing** on stdout, so a caller never records anything but a URL or `local` as `pr:`.
4. `forge.sh pr-state URL` SHALL print one of `OPEN|MERGED|CLOSED|UNKNOWN` and SHALL fail closed.
   - **gitlab:** given a GitLab MR URL (`…/-/merge_requests/<iid>`), when it runs, then the API states map as follows: `opened`→`OPEN`, `merged`→`MERGED`, `closed`→`CLOSED`. Any other state, including `locked` (transient during a merge), maps to `UNKNOWN`.
   - **gitlab project path:** the project path is everything between the host and `/-/merge_requests/`, at any depth (subgroups included), and it is fully URL-encoded as the project id. Given `FORGE_URL` with a path prefix (an instance served under a sub-path) that the MR URL starts with, then the base is `FORGE_URL` and the project path is the remainder.
   - **github:** given a PR URL of the shape `https://<host>/<owner>/<repo>/pull/<n>` whose host is `github.com` **or the configured GitHub instance** (the host of `FORGE_URL`, else of the remote, when the kind is `github`; GitHub Enterprise included), when it runs, then it reports `gh`'s state for that URL. Given such a URL on any other host, then it prints `UNKNOWN` without invoking `gh`, because `gh` would offer an enterprise credential to whatever host a spec file names (see acceptance 5).
   - **adapter from the URL:** the adapter is chosen from the URL's shape, not from the current repo's `kind`, so a recorded URL stays readable after a project changes forge.
   - **fail closed:** given `local`, an empty value, a non-https value, an unparseable URL, a missing credential, a missing `gh`, or any request error, when it runs, then it prints `UNKNOWN` and exits 0. It never prints `MERGED` without a successful response saying so.
5. GitLab credentials SHALL be sent only to the configured GitLab instance.
   - **host binding:** the configured instance is `FORGE_URL` if set, else the base derived from the remote (below). Given a `pr:` URL (pr-state, pr-close) whose scheme, host and port differ from it, when the operation runs, then **no request is made**: `pr-state` prints `UNKNOWN`, and `pr-close` exits non-zero naming the mismatch.
   - **positive control:** a URL on the configured instance does reach the transport.
   - **why:** a spec file's `pr:` is data that `reconcile-done` reads unattended, and it must never be able to send the token elsewhere.

5b. GitLab credentials SHALL be resolved in this exact order, and SHALL never appear in a child process's argv or on disk: `FORGE_TOKEN` from the environment, then `FORGE_TOKEN` in `./.env`, then `GITLAB_TOKEN` from the environment, then `GITLAB_TOKEN` in `./.env`. The first non-empty value wins.
   - **self-contained:** `forge.sh` reads `./.env` itself and does not depend on any other library for it, because acceptance 8 invokes it from `tracker.sh`, which only sources `obs.sh`.
   - **base URL:** given `FORGE_URL`, when a GitLab request is made, then that is the base. Given none and an https remote, then the base is that remote's scheme, host and port. Given none and an ssh remote, then the base is `https://<host>` with no port.
   - **token never exposed:** given any GitLab operation, when it runs, then the token is not part of any process argument list and no file containing it is created, including temporary files.
6. `forge.sh push BRANCH` SHALL push to the configured remote with upstream tracking.
   - **gitlab over https:** given kind `gitlab`, an https remote and a token, when it runs, then git authenticates with the token through configuration scoped to that remote's URL and passed via the environment, never via argv or a written config file.
   - **any other case:** given an ssh remote, or kind `github`/`none`, when it runs, then it is a plain `git push -u <remote> <BRANCH>` with no injected credentials.
7. `forge.sh pr-close URL` SHALL close the PR/MR and SHALL be reachable only behind explicit human confirmation.
   - Given a GitLab or GitHub URL, when it runs, then the PR/MR is closed and the resulting state is printed.
   - Given `skills/shelve/SKILL.md`, when it describes closing a PR/MR, then it names `forge.sh pr-close`, keeps the rule that it is never run unprompted or in an unattended loop, and no longer contains `gh pr close`.
   - Given `templates/workflows/factory.js` and `skills/review/SKILL.md` (the unattended stages), then neither contains the string `pr-close` at all.
8. `tracker.sh reconcile-done` SHALL read forge state through `forge.sh` and keep its git-first, fail-closed order.
   - **git first:** given a `pr-open` spec whose branch is an ancestor of the default branch, when reconcile runs, then it advances to `done` without any forge call.
   - **merged by forge:** given a `pr-open` spec whose branch is not an ancestor and whose `pr:` is an https URL that `forge.sh pr-state` reports `MERGED`, when reconcile runs, then it advances to `done`.
   - **open or unknown:** given the same spec but `OPEN` or `UNKNOWN`, when reconcile runs, then the spec is untouched.
   - **invoked, not sourced:** reconcile calls `forge.sh pr-state` as a subprocess when an executable `forge.sh` sits beside `tracker.sh`. A non-zero exit, or output outside `OPEN|MERGED|CLOSED|UNKNOWN`, counts as `UNKNOWN`.
   - **older scaffold:** given a project scaffolded before this spec, with no `scripts/lib/forge.sh` beside `tracker.sh`, when reconcile runs, then today's `gh pr view` fallback behaves exactly as before.
9. The review stage SHALL push and open PRs/MRs through `forge.sh` and record what it prints.
   - Given `skills/review/SKILL.md` step 9 and the `review-prompt` plugin region of `templates/workflows/factory.js`, when they describe pushing and opening, then they name `scripts/lib/forge.sh push` and `pr-create`, record the printed value as `pr:`, and keep `pr: local` as the no-forge outcome.
   - **stale text gone:** `skills/review/SKILL.md` no longer contains `git push -u origin`. For `templates/workflows/factory.js`, which never contained it, the assertion is presence: the `review-prompt` region names `forge.sh push` and `pr-create`.
   - The text says PR/MR rather than assuming GitHub.
10. `forge.sh check` SHALL see the environment doctor was started with. Today doctor loads `./.env` into its own environment (`set -a; source ./.env`), which would make `.env` values look like environment values. `check` must therefore run with the pre-load environment, either before that load or in an environment restored from a snapshot taken before it, so acceptance 1's precedence and its source reporting hold under doctor too.

10b. `forge.sh check` SHALL emit one line per finding, in the form `ok|warn|fail<TAB>message`, and exit 0. `doctor.sh` SHALL run it and report each line through the existing `ok`/`warn`/`fail` helpers in a `forge:` section. doctor itself makes no forge call.
    - **kind:** given any project, when doctor runs, then it reports the resolved kind and where it came from (env, `.env`, config, auto). Given `FORGE` set only in `./.env`, when doctor runs, then the source reported is `.env`, not env.
    - **github:** given kind `github`, when doctor runs, then a missing `gh` or failed `gh auth status` is `fail`, and an authenticated `gh` is `ok`.
    - **gitlab:** given kind `gitlab`, when doctor runs, then a missing token is `fail`, an authenticated `GET /user` is `ok`, and an HTTP 401/403 is `fail`. A transport error (no connection, timeout) or a 5xx is `warn`, never `fail`, because offline is a normal state.
    - **config:** given `.agentic/config.json` present but malformed, when doctor runs, then `check` emits a `warn` saying the forge config was ignored.
    - **none:** given kind `none` with a remote, when doctor runs, then it warns naming the remote host and how to declare the forge. Given no remote, then it reports that PRs will be recorded as `pr: local`.
11. Projects SHALL receive and be able to configure the forge layer.
    - **delivery:** given `/agentic-loop:init` or `/agentic-loop:update`, when they run, then `scripts/lib/forge.sh` is copied: it has a row in the `scripts/lib/scaffold.sh` manifest and appears in the `skills/init/SKILL.md` copy list.
    - **settings:** given `templates/.env.example`, then it documents `FORGE`, `FORGE_URL`, `FORGE_REMOTE`, `FORGE_TOKEN` and `GITLAB_TOKEN` with placeholder values. Given `skills/config/SKILL.md`, then it documents `forge.kind` and `forge.remote`.
12. Every pre-existing free eval suite SHALL still pass.
    - Given `./evals/run_eval.sh` (free kinds), when it runs after this change, then it reports 0 failures.

## Check command (the Red Gate contract)

```
check_cmd: ./evals/run_eval.sh --suite forge
```

**Build order (spec 004 acceptance 7).** This is a new suite. Write the cases
first, see them genuinely fail (exit 1 against a tree without `forge.sh`), then
implement. Acceptance 12 is checked by the review stage running the full free
suite.

**No eval case may reach the network, and the seam is the real process boundary.**
Shims for `curl`, `gh` and `git` (where push auth is under test) sit first on
`PATH`, so what they see is the real argv `forge.sh` produced, not an
in-process stand-in.
- Each shim appends its argv, and for `git` the names (not values) of the
  `GIT_CONFIG_*` variables plus the scoped config key, to a log under
  `FORGE_MOCK_DIR`.
- **Request transport contract (so the seam can see requests without seeing
  the token):**
  - request fields go on curl's argv as `--data-urlencode name=value`, or
    `name@file` for the description, so the shim can read them from argv and
    the named file;
  - **only** the auth header travels on stdin (`--config -` / `-H @-`);
  - the shim records just whether stdin carried an auth header, as
    `auth=present` or `auth=absent`, never its value;
  - the stdin itself is never logged.
- The `curl` shim answers from canned files in `FORGE_MOCK_DIR` keyed by method
  and path. **Any unknown host or path** is logged and answered with curl's
  connection-error exit code. That covers doctor's other probes (the local
  Ollama server, the OpenRouter catalog): they degrade to doctor's existing
  "unreachable" warnings, and doctor cases assert only on lines from the
  `forge:` section. A canned file can also specify an HTTP status (401, 404, 409, 5xx)
  or a transport failure (the shim exits with curl's connection-error code), so
  acceptance 10's `warn` versus `fail` split and acceptance 4's fail-closed
  paths are both exercisable.
- Hosts are RFC 2606 placeholders (`gitlab.example.test`; `github.com` only as
  a string), and tokens are obviously fake values.

**Every negative assertion needs a positive control in the same run.**
- A case asserting "zero requests" (acceptance 1), "no forge call" (acceptance
  8, git first) or "token in no argv" (acceptance 5) must also run an operation
  in that case that demonstrably reached the shim, and assert that the log is
  non-empty and has the expected method and path. Otherwise an implementation
  that bypasses the shim (real `curl` by absolute path) or bails early passes
  trivially.
- For acceptance 5, scan both the shim's argv log and the files under the
  sandbox, `TMPDIR` and `/tmp` that changed during the case, and assert the fake
  token appears in none of them.
- The doc acceptances (7, 9) are checked with both the presence **and** the
  absence greps stated in them.

**No case may pass by asserting nothing.** `run_eval.sh` fails a case only
through its `checks[]`. A case with none, or with checks that never examine
the behaviour, passes.
- Every case carries an `exit_code` check **and** at least one check on output
  or the shim log.
- Case ids carry the acceptance they cover (`forge-NNN-a<N>-slug`), and one meta
  case asserts that every acceptance 1–11 (with 5b and 10b) has at least one
  case.
- The Red Gate is observed per case: against a tree without `forge.sh`, every
  forge case fails, not merely the suite as a whole.

With cases present, a tree without `forge.sh` makes them fail, so the suite
exits 1 (not 4, which means nothing ran).

**Mutation-test acceptance 4 in the dangerous direction.** Make `pr-state`
print `MERGED` on a request error, and confirm a case fails. A state check that
reports merged when it could not look would advance a spec to `done` and
unblock its dependents on nothing. That is the defect class
`_tracker_supersede_lands` was written to prevent.

Cases are `kind: bash-unit`. Acceptance 8's "older scaffold" case copies
`tracker.sh` and `obs.sh` into a sandbox without `forge.sh` and uses the `gh`
shim.

## Notes / decisions (append-only)

- **Detection is declared, never probed** (owner ruling 2026-11-16).
  Self-hosted GitLab can live under any hostname. A network probe would make
  forge detection, and with it the unattended review stage, depend on
  reachability and timing. A host that is neither `github.com` nor contains
  `gitlab` resolves to `none`, which degrades to the existing `pr: local`
  path, and `doctor.sh` says how to declare the forge.
- **Reviewer assignment is project policy, not plugin behaviour** (owner
  ruling 2026-11-16). Who reviews is local knowledge: names, teams, rotation.
  The plugin already has a project-owned seam for it
  (`PROJECT_REVIEW_ADDENDUM`, plus a project's own `CLAUDE.md`/`AGENTS.md`),
  so shipping a `forge.reviewers` knob would duplicate it.

- **triage** (build, first `check_cmd` failure: 70/72; cases 410 and 411)
  reproduce: in a bash-unit sandbox, gitlab remote, fake FORGE_TOKEN, `fx_http "GET /api/v4/user" 401`, then `forge.sh check` printed only the `ok` kind line and died on stderr with `_GL_STATUS: unbound variable`. The request reached the curl shim (requests.log `GET …/api/v4/user auth=present`).
  localize: `scripts/lib/forge.sh` `forge_check` gitlab branch, `out="$(_forge_gl_api GET …)"`, followed by `case "$_GL_STATUS"`. `_forge_gl_api` sets the global `_GL_STATUS`, but it runs inside a command substitution (a subshell), so the caller never sees it. The same pattern appears in `_forge_gitlab_pr_create`/`_pr_close` error messages.
  hypothesis: the HTTP status is lost across the `$(...)` boundary, so under `set -u` check aborts before it can emit the 401/403 `fail` or the transport/5xx `warn` line.
  evidence: the unbound-variable error at the `case` line; the doctor `forge:` section holds only the `[ok]` line; case 409 (200) passes because the success branch never reads `_GL_STATUS`. The diagnosis came from a blind loop-reviewer pass (spec, failure output and diff only).

## Revision log (deltas only — never regenerate this spec)

- 2026-11-16 spec: ADDED initial spec after two grilling questions (detection, reviewers).
- 2026-11-16 spec-review: MODIFIED output_spec — doctor goes through `forge.sh check`, and the legacy `gh` fallback is the stated sole exception (was a false "only place" claim).
- 2026-11-16 spec-review: ADDED acceptance 10 `check` contract (`ok|warn|fail<TAB>msg`, exit 0); 401/403 is fail, transport error or 5xx is warn; malformed config is warn.
- 2026-11-16 spec-review: MODIFIED test seam — `curl`/`gh`/`git` shims on PATH with status and transport-failure injection; positive controls are mandatory for every negative assertion; the token scan covers the shim log, sandbox, TMPDIR and /tmp.
- 2026-11-16 spec-review: ADDED edge cases — case-insensitive label-prefix `gitlab` match, `www.github.com`, GitHub Enterprise → none unless declared, empty `FORGE=` = undeclared, malformed config = no config, a missing remote name → none, the exact token precedence, subgroups and path-prefixed instances, `/pull/` URLs on any host via `gh`.
- 2026-11-16 spec-review: MODIFIED acceptance 4 — `locked` maps to UNKNOWN (fail closed), not CLOSED.
- 2026-11-16 spec-review: ADDED absence checks — no `gh pr close` in shelve, no `pr-close` in unattended stages, no `git push -u origin` in review step 9 or factory.js; `local` is the sole non-URL `pr:`.
- 2026-11-16 spec-review-2: ADDED acceptance 5 host binding — the token only goes to the configured instance, and a foreign `pr:` host means no request (UNKNOWN, or refusal on close).
- 2026-11-16 spec-review-2: ADDED acceptance 10 — `check` runs with doctor's pre-`.env` environment, so precedence and source reporting hold; token order moved to 5b, and the check contract to 10b.
- 2026-11-16 spec-review-2: ADDED missing-remote behaviour — a declared kind still resolves; `push` is a no-op with exit 0; `pr-create` prints `local`.
- 2026-11-16 spec-review-2: ADDED project-id derivation for https, scp and ssh remotes (`.git` stripped, FORGE_URL prefix removed); GitHub `pr-create` is idempotent via a lookup first.
- 2026-11-16 spec-review-2: ADDED request transport contract (fields in argv, auth on stdin, shim logs `auth=present|absent` only); the unknown-path shim answer is a connection error; doctor cases assert only on the forge section; acceptance 9's factory.js half is a presence assertion; every case needs `exit_code` plus a behaviour check, a meta case checks coverage, and the Red Gate is per case.
- 2026-11-16 review: MODIFIED acceptance 4 (github) — `/pull/` URLs are read via `gh` only for github.com or the configured GitHub instance, else UNKNOWN with no `gh` call. This extends acceptance 5's host binding to `gh`'s enterprise credentials (blind-review finding; a tightening, no user decision needed).
- 2026-11-16 review: blind review verdict pass (73/73; reviewer mutations of pr-state, host binding, locked state and push auth each caught). Revision round 1 (of max 2) fixed 6 impl findings, each with a Red-Gate case first (343, 344, 354, 363, 364, 365, 329, 338; 333 updated): a scheme-less FORGE_URL is refused (token never sent over http); the https push injects the token only for the configured instance; the github adapter passes --repo for the configured remote; option-like branch and remote names are refused; the URL authority is cut at the first of / ? # with backslash and whitespace refused; tokens outside [A-Za-z0-9._~-] are refused, and caller GIT_CONFIG_* entries are preserved. Result: forge 81/81, full free suite 454 pass, 0 fail.
