#!/usr/bin/env bash
# forge.sh — the forge seam: every forge operation the factory performs goes
# through here (spec 020). Sourceable library + CLI, same shape as tracker.sh.
#
#   forge.sh kind                 github | gitlab | none
#   forge.sh remote               the git remote the forge layer acts on
#   forge.sh push BRANCH          push with upstream tracking
#   forge.sh pr-create --head B --base T --title S --body-file F
#                                 open ONE PR/MR, print only its URL (or `local`)
#   forge.sh pr-state URL         OPEN | MERGED | CLOSED | UNKNOWN (fails closed)
#   forge.sh pr-close URL         close it — human-confirmed use only (shelve)
#   forge.sh check                doctor lines: ok|warn|fail<TAB>message
#
# Resolution (spec 020 acceptance 1): FORGE in the environment, then FORGE in
# ./.env, then .forge.kind in .agentic/config.json, then auto-detection from
# the remote host. Detection NEVER touches the network: a self-hosted forge can
# live under any hostname, and the unattended review stage must not depend on
# reachability. Unrecognised hosts resolve to `none`, which degrades to the
# existing `pr: local` path until the forge is declared.
#
# Adapter contract — adding a forge (Gitea/Forgejo, Bitbucket, ...):
#   1. teach _forge_auto / _forge_valid_kind the new kind;
#   2. implement _forge_<kind>_pr_create, _forge_<kind>_pr_state,
#      _forge_<kind>_pr_close and _forge_<kind>_check with the same
#      stdout/exit contract as the gitlab ones below;
#   3. teach _forge_url_kind to recognise its PR URL shape.
# Callers (review skill, tracker reconcile, shelve, doctor) never change.
#
# Credentials (gitlab): FORGE_TOKEN (env, then ./.env), then GITLAB_TOKEN
# (env, then ./.env). The token is only ever sent to the configured instance
# (FORGE_URL, else the remote's base) and only via curl's stdin config or a
# GIT_CONFIG_* environment variable — never argv, never a file.

set -uo pipefail

_FORGE_CFG_FILE="${FORGE_CONFIG_FILE:-.agentic/config.json}"
_FORGE_SRC=""   # where the last resolved kind came from: env|.env|config|auto

_forge_die() { echo "forge: $*" >&2; return 1; }

_forge_lower() { tr '[:upper:]' '[:lower:]'; }

# _forge_dotenv KEY — value of KEY in ./.env (first match), quotes stripped.
_forge_dotenv() {
  [[ -f ./.env ]] || return 0
  local line
  line="$(grep -m1 -E "^[[:space:]]*(export[[:space:]]+)?$1=" ./.env 2>/dev/null || true)"
  [[ -n "$line" ]] || return 0
  line="${line#*=}"
  line="${line%$'\r'}"
  line="${line#\"}"; line="${line%\"}"
  line="${line#\'}"; line="${line%\'}"
  printf '%s' "$line"
}

# _forge_setting KEY — environment first, then ./.env. Empty means unset.
_forge_setting() {
  local v="${!1:-}"
  [[ -n "$v" ]] || v="$(_forge_dotenv "$1")"
  printf '%s' "$v"
}

# _forge_cfg KEY — .forge.KEY from the project config; absent or malformed
# config counts as no config (acceptance 1).
_forge_cfg() {
  [[ -f "$_FORGE_CFG_FILE" ]] || return 0
  jq -r --arg k "$1" '(.forge // {})[$k] // empty | strings' "$_FORGE_CFG_FILE" 2>/dev/null || true
}

_forge_cfg_malformed() {
  [[ -f "$_FORGE_CFG_FILE" ]] || return 1
  ! jq -e . "$_FORGE_CFG_FILE" >/dev/null 2>&1
}

forge_remote() {
  local r
  r="$(_forge_setting FORGE_REMOTE)"
  [[ -n "$r" ]] || r="$(_forge_cfg remote)"
  printf '%s' "${r:-origin}"
}

# The remote's URL, empty when the remote does not exist (or no repo).
_forge_remote_url() {
  local r; r="$(forge_remote)"
  [[ "$r" == -* ]] && return 0   # option-like: never hand it to git
  git remote get-url "$r" 2>/dev/null || true
}

# _forge_parse URL — sets _P_SCHEME (https|http|ssh), _P_HOST (lowercased),
# _P_PORT (may be empty), _P_PATH (repo path, no leading slash, no .git).
_forge_parse() {
  local u="$1" rest hostport
  _P_SCHEME=""; _P_HOST=""; _P_PORT=""; _P_PATH=""
  case "$u" in
    http://*|https://*|ssh://*)
      _P_SCHEME="${u%%://*}"; rest="${u#*://}"
      # The authority ends at the FIRST of / ? # — what a real URL parser
      # does. Cutting at '/' only let `https://evil#@good/...` read as host
      # `good` and pass the host binding (020 review finding).
      hostport="${rest%%[/?#]*}"; _P_PATH="${rest#"$hostport"}"
      _P_PATH="${_P_PATH%%[?#]*}"
      [[ "$hostport" != *[\\[:space:]]* ]] || return 1
      hostport="${hostport##*@}"
      ;;
    *@*:*|*:*)
      # scp-style: [user@]host:path
      [[ "$u" == */* || "$u" == *:* ]] || return 1
      _P_SCHEME=ssh; rest="${u#*@}"
      hostport="${rest%%:*}"; _P_PATH="${rest#*:}"
      ;;
    *) return 1 ;;
  esac
  if [[ "$hostport" == *:* ]]; then _P_PORT="${hostport##*:}"; hostport="${hostport%:*}"; fi
  _P_HOST="$(printf '%s' "$hostport" | _forge_lower)"
  _P_PATH="${_P_PATH#/}"; _P_PATH="${_P_PATH%/}"; _P_PATH="${_P_PATH%.git}"
  [[ -n "$_P_HOST" ]]
}

_forge_valid_kind() { [[ "$1" == github || "$1" == gitlab || "$1" == none ]]; }

# _forge_auto HOST — detection by host only, case-insensitive, no network.
_forge_auto() {
  local host lbl
  host="$(printf '%s' "$1" | _forge_lower)"
  [[ -n "$host" ]] || { printf none; return; }
  if [[ "$host" == github.com || "$host" == www.github.com ]]; then printf github; return; fi
  IFS=. read -r -a _labels <<<"$host"
  for lbl in "${_labels[@]}"; do
    [[ "$lbl" == gitlab* ]] && { printf gitlab; return; }
  done
  printf none
}

# forge_kind — prints the kind; exits non-zero (stdout empty) on a bad value.
forge_kind() {
  local v url
  v="${FORGE:-}"; _FORGE_SRC=env
  if [[ -z "$v" ]]; then v="$(_forge_dotenv FORGE)"; _FORGE_SRC=.env; fi
  if [[ -z "$v" ]]; then v="$(_forge_cfg kind)"; _FORGE_SRC=config; fi
  if [[ -n "$v" ]]; then
    v="$(printf '%s' "$v" | _forge_lower)"
    _forge_valid_kind "$v" || { _forge_die "invalid forge kind '$v' (from $_FORGE_SRC) — use github, gitlab or none"; return 2; }
    printf '%s\n' "$v"; return 0
  fi
  _FORGE_SRC=auto
  url="$(_forge_remote_url)"
  if [[ -z "$url" ]] || ! _forge_parse "$url"; then printf 'none\n'; return 0; fi
  printf '%s\n' "$(_forge_auto "$_P_HOST")"
}

# --- gitlab transport ---------------------------------------------------------

# A token is interpolated into a curl config line and a git header: anything
# outside the PAT alphabet could break out of the quotes (020 review finding).
_forge_token_ok() { [[ "$1" =~ ^[A-Za-z0-9._~-]+$ ]]; }

_forge_token() {
  local t
  t="$(_forge_setting FORGE_TOKEN)"
  [[ -n "$t" ]] || t="$(_forge_setting GITLAB_TOKEN)"
  printf '%s' "$t"
}

# _forge_gl_base — the configured instance: FORGE_URL, else derived from the
# remote (https keeps scheme/host/port; ssh becomes https://host, no port).
_forge_gl_base() {
  local b url
  b="$(_forge_setting FORGE_URL)"
  if [[ -n "$b" ]]; then
    # No scheme means curl would speak plain http and send the token in the
    # clear. Refuse rather than guess (020 review finding).
    [[ "$b" == https://* || "$b" == http://* ]] \
      || { echo "forge: FORGE_URL must start with https:// (got '$b')" >&2; return 1; }
    printf '%s' "${b%/}"; return 0
  fi
  url="$(_forge_remote_url)"
  [[ -n "$url" ]] && _forge_parse "$url" || return 1
  if [[ "$_P_SCHEME" == http || "$_P_SCHEME" == https ]]; then
    printf '%s://%s%s' "$_P_SCHEME" "$_P_HOST" "${_P_PORT:+:$_P_PORT}"
  else
    printf 'https://%s' "$_P_HOST"
  fi
}

# _forge_origin_of URL — scheme://host[:port], lowercased host.
_forge_origin_of() {
  _forge_parse "$1" || return 1
  printf '%s://%s%s' "$_P_SCHEME" "$_P_HOST" "${_P_PORT:+:$_P_PORT}"
}

_forge_urlencode() { jq -rn --arg s "$1" '$s|@uri'; }

# _forge_gl_project_enc — URL-encoded project id from the remote path, with a
# FORGE_URL path prefix removed for https remotes.
_forge_gl_project_enc() {
  local url path prefix base
  url="$(_forge_remote_url)"
  [[ -n "$url" ]] && _forge_parse "$url" || return 1
  path="$_P_PATH"
  base="$(_forge_setting FORGE_URL)"
  if [[ -n "$base" && ( "$_P_SCHEME" == https || "$_P_SCHEME" == http ) ]]; then
    _forge_parse "$base" && prefix="$_P_PATH"
    if [[ -n "${prefix:-}" && "$path" == "$prefix"/* ]]; then path="${path#"$prefix"/}"; fi
  fi
  _forge_urlencode "$path"
}

# _forge_gl_api OUTVAR METHOD BASE APIPATH [curl data args...] — the body is
# stored in OUTVAR and the HTTP status in _GL_STATUS ("000" on transport
# failure). Returns 0 on 2xx. Call it DIRECTLY, never inside $(...): a command
# substitution is a subshell, and _GL_STATUS would be lost to the caller (the
# 020 build triage — check's 401 line and pr-create's error message both read it).
_forge_gl_api() {
  local _outvar="$1" method="$2" base="$3" path="$4" tok body rc
  shift 4
  _GL_STATUS=000
  printf -v "$_outvar" '%s' ""
  tok="$(_forge_token)"
  [[ -n "$tok" ]] || { echo "forge: no GitLab token (set FORGE_TOKEN or GITLAB_TOKEN in ./.env)" >&2; return 1; }
  _forge_token_ok "$tok" || { echo "forge: the GitLab token contains characters outside [A-Za-z0-9._~-] — refusing to use it" >&2; return 1; }
  body="$(mktemp "${TMPDIR:-/tmp}/forge.XXXXXX")" || return 1
  _GL_STATUS="$(printf 'header = "PRIVATE-TOKEN: %s"\n' "$tok" \
    | curl -sS --max-time 20 -K - -X "$method" "$@" -o "$body" -w '%{http_code}' \
        "$base/api/v4$path" 2>/dev/null)"
  rc=$?
  [[ $rc -eq 0 && -n "$_GL_STATUS" ]] || _GL_STATUS=000
  printf -v "$_outvar" '%s' "$(cat "$body")"; rm -f "$body"
  [[ "$_GL_STATUS" == 2?? ]]
}

# _forge_gl_from_url URL — for a recorded MR URL, set _MR_BASE, _MR_ENC, _MR_IID.
# Refuses (non-zero) when the URL is not on the configured instance: the token
# must never be sent to a host a spec file merely names (acceptance 5).
_forge_gl_from_url() {
  local url="$1" origin configured cfg_path proj
  [[ "$url" == https://*"/-/merge_requests/"* ]] || return 1
  _MR_IID="${url##*/-/merge_requests/}"; _MR_IID="${_MR_IID%%[/?#]*}"
  [[ "$_MR_IID" =~ ^[0-9]+$ ]] || return 1
  origin="$(_forge_origin_of "$url")" || return 1
  configured="$(_forge_gl_base)" || return 1
  _forge_parse "$configured" || return 1
  cfg_path="$_P_PATH"
  [[ "$(_forge_origin_of "$configured")" == "$origin" ]] || { echo "forge: $origin is not the configured GitLab instance — refusing to send credentials there" >&2; return 3; }
  proj="${url#"$origin"/}"; proj="${proj%%/-/merge_requests/*}"
  if [[ -n "$cfg_path" && "$proj" == "$cfg_path"/* ]]; then proj="${proj#"$cfg_path"/}"; fi
  [[ -n "$proj" ]] || return 1
  _MR_BASE="$configured"
  _MR_ENC="$(_forge_urlencode "$proj")"
}

_forge_gitlab_pr_create() {
  local head="$1" base_br="$2" title="$3" bodyf="$4" base enc url
  base="$(_forge_gl_base)" && enc="$(_forge_gl_project_enc)" || { echo "forge: cannot derive the GitLab project from the remote" >&2; return 1; }
  # Idempotency: an open MR for this source branch is THE MR.
  local out=""
  if _forge_gl_api out GET "$base" "/projects/$enc/merge_requests?source_branch=$(_forge_urlencode "$head")&state=opened"; then
    url="$(jq -r '.[0].web_url // empty' <<<"$out" 2>/dev/null)"
    [[ -n "$url" ]] && { printf '%s\n' "$url"; return 0; }
  fi
  if ! _forge_gl_api out POST "$base" "/projects/$enc/merge_requests" \
        --data-urlencode "source_branch=$head" --data-urlencode "target_branch=$base_br" \
        --data-urlencode "title=$title" --data-urlencode "description@$bodyf"; then
    echo "forge: GitLab create failed (HTTP $_GL_STATUS)" >&2; return 1
  fi
  url="$(jq -r '.web_url // empty' <<<"$out" 2>/dev/null)"
  [[ -n "$url" ]] || { echo "forge: GitLab response carried no web_url" >&2; return 1; }
  printf '%s\n' "$url"
}

_forge_gitlab_pr_state() {
  local out="" st
  _forge_gl_from_url "$1" || { echo UNKNOWN; return 0; }
  _forge_gl_api out GET "$_MR_BASE" "/projects/$_MR_ENC/merge_requests/$_MR_IID" || { echo UNKNOWN; return 0; }
  st="$(jq -r '.state // empty' <<<"$out" 2>/dev/null)"
  case "$st" in
    opened) echo OPEN ;;
    merged) echo MERGED ;;
    closed) echo CLOSED ;;
    *)      echo UNKNOWN ;;   # incl. `locked` — transient mid-merge; fail closed
  esac
}

_forge_gitlab_pr_close() {
  local rc
  _forge_gl_from_url "$1"; rc=$?
  [[ $rc -eq 0 ]] || { [[ $rc -eq 3 ]] || echo "forge: not a GitLab MR URL: $1" >&2; return 1; }
  local out=""
  _forge_gl_api out PUT "$_MR_BASE" "/projects/$_MR_ENC/merge_requests/$_MR_IID" \
    --data-urlencode "state_event=close" || { echo "forge: GitLab close failed (HTTP $_GL_STATUS)" >&2; return 1; }
  _forge_gitlab_pr_state "$1"
}

# --- github adapter (gh) --------------------------------------------------------

# _forge_gh_repo — the --repo value for the configured remote: OWNER/REPO on
# github.com, HOST/OWNER/REPO elsewhere. gh would otherwise infer the repo on
# its own, which may not be the remote push targeted (020 review finding).
_forge_gh_repo() {
  local url; url="$(_forge_remote_url)"
  [[ -n "$url" ]] && _forge_parse "$url" || return 1
  if [[ "$_P_HOST" == github.com || "$_P_HOST" == www.github.com ]]; then printf '%s' "$_P_PATH"
  else printf '%s/%s' "$_P_HOST" "$_P_PATH"; fi
}

_forge_github_pr_create() {
  local head="$1" base_br="$2" title="$3" bodyf="$4" url repo
  command -v gh >/dev/null 2>&1 || { echo "forge: gh not installed" >&2; return 1; }
  repo="$(_forge_gh_repo)" || { echo "forge: cannot derive the GitHub repo from the remote" >&2; return 1; }
  url="$(gh pr list --repo "$repo" --head "$head" --state open --json url --jq '.[0].url' 2>/dev/null || true)"
  if [[ "$url" == https://* ]]; then printf '%s\n' "$url"; return 0; fi
  url="$(gh pr create --repo "$repo" --head "$head" --base "$base_br" --title "$title" --body-file "$bodyf" 2>&1)" \
    || { echo "forge: gh pr create failed: $url" >&2; return 1; }
  url="$(printf '%s\n' "$url" | grep -E '^https://' | tail -1)"
  [[ -n "$url" ]] || { echo "forge: gh pr create printed no URL" >&2; return 1; }
  printf '%s\n' "$url"
}

# _forge_gh_host_ok URL — gh is only pointed at github.com or the configured
# GitHub instance: given any other host, gh could offer an enterprise
# credential to whatever host a spec file names (spec 020 acceptance 4).
_forge_gh_host_ok() {
  local host cfg="" b k
  _forge_parse "$1" || return 1
  host="$_P_HOST"
  [[ "$host" == github.com || "$host" == www.github.com ]] && return 0
  k="$(forge_kind 2>/dev/null)" || return 1
  [[ "$k" == github ]] || return 1
  b="$(_forge_setting FORGE_URL)"
  if [[ -n "$b" ]]; then _forge_parse "$b" && cfg="$_P_HOST"
  else b="$(_forge_remote_url)"; [[ -n "$b" ]] && _forge_parse "$b" && cfg="$_P_HOST"; fi
  [[ -n "$cfg" && "$host" == "$cfg" ]]
}

_forge_github_pr_state() {
  local st
  _forge_gh_host_ok "$1" || { echo UNKNOWN; return 0; }
  command -v gh >/dev/null 2>&1 || { echo UNKNOWN; return 0; }
  st="$(gh pr view "$1" --json state --jq .state 2>/dev/null || true)"
  case "$st" in OPEN|MERGED|CLOSED) echo "$st" ;; *) echo UNKNOWN ;; esac
}

_forge_github_pr_close() {
  _forge_gh_host_ok "$1" || { echo "forge: $1 is not on github.com or the configured GitHub instance — refusing" >&2; return 1; }
  command -v gh >/dev/null 2>&1 || { echo "forge: gh not installed" >&2; return 1; }
  gh pr close "$1" >/dev/null 2>&1 || { echo "forge: gh pr close failed" >&2; return 1; }
  _forge_github_pr_state "$1"
}

# The adapter for a RECORDED url comes from its shape, not the repo's kind, so
# a pr: stays readable after a project changes forge (acceptance 4).
_forge_url_kind() {
  case "$1" in
    https://*/-/merge_requests/*) echo gitlab ;;
    https://*/*/*/pull/*)         echo github ;;
    *)                            echo none ;;
  esac
}

# --- public operations ------------------------------------------------------------

forge_pr_state() {
  local url="${1:-}"
  case "$(_forge_url_kind "$url")" in
    gitlab) _forge_gitlab_pr_state "$url" ;;
    github) _forge_github_pr_state "$url" ;;
    *)      echo UNKNOWN ;;
  esac
  return 0
}

forge_pr_close() {
  local url="${1:-}"
  case "$(_forge_url_kind "$url")" in
    gitlab) _forge_gitlab_pr_close "$url" ;;
    github) _forge_github_pr_close "$url" ;;
    *)      _forge_die "not a PR/MR URL: '$url'" ;;
  esac
}

forge_pr_create() {
  local head="" base="" title="" bodyf="" kind
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --head) head="${2:-}"; shift 2 ;;
      --base) base="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --body-file) bodyf="${2:-}"; shift 2 ;;
      *) _forge_die "pr-create: unknown argument '$1'"; return 1 ;;
    esac
  done
  [[ -n "$head" && -n "$base" && -n "$title" && -f "$bodyf" ]] \
    || { _forge_die "usage: pr-create --head B --base T --title S --body-file F"; return 1; }
  kind="$(forge_kind)" || return 1
  if [[ -z "$(_forge_remote_url)" || "$kind" == none ]]; then echo local; return 0; fi
  case "$kind" in
    gitlab) _forge_gitlab_pr_create "$head" "$base" "$title" "$bodyf" ;;
    github) _forge_github_pr_create "$head" "$base" "$title" "$bodyf" ;;
  esac
}

forge_push() {
  local branch="${1:-}" remote url kind tok origin cfg n
  [[ -n "$branch" ]] || { _forge_die "usage: push BRANCH"; return 1; }
  remote="$(forge_remote)"
  # Option-like names would be parsed by git as options (--receive-pack=...).
  [[ "$branch" != -* ]] || { _forge_die "refusing option-like branch name '$branch'"; return 1; }
  [[ "$remote" != -* ]] || { _forge_die "refusing option-like remote name '$remote'"; return 1; }
  url="$(_forge_remote_url)"
  if [[ -z "$url" ]]; then echo "no remote" >&2; return 0; fi
  kind="$(forge_kind)" || return 1
  tok="$(_forge_token)"
  if [[ "$kind" == gitlab && "$url" == https://* && -n "$tok" ]] && _forge_token_ok "$tok"; then
    origin="$(_forge_origin_of "$url")"
    cfg="$(_forge_gl_base 2>/dev/null)" && cfg="$(_forge_origin_of "$cfg")" || cfg=""
    # Only to the configured instance (acceptance 5) — a mirror remote gets a
    # plain push. Scoped to that origin and passed through the environment
    # (export is a builtin: never argv, never a written config file), appended
    # after any GIT_CONFIG_* entries the caller already set.
    if [[ -n "$cfg" && "$origin" == "$cfg" ]]; then
      (
        n="${GIT_CONFIG_COUNT:-0}"
        [[ "$n" =~ ^[0-9]+$ ]] || n=0
        export GIT_CONFIG_COUNT=$((n + 1))
        export "GIT_CONFIG_KEY_$n=http.${origin}/.extraheader"
        export "GIT_CONFIG_VALUE_$n=Authorization: Basic $(printf 'oauth2:%s' "$tok" | base64 | tr -d '\n')"
        git push -u "$remote" "$branch"
      )
      return
    fi
  fi
  git push -u "$remote" "$branch"
}

# forge_check — doctor lines "ok|warn|fail<TAB>message", always exit 0.
forge_check() {
  local kind src url host base out
  _line() { printf '%s\t%s\n' "$1" "$2"; }
  if _forge_cfg_malformed; then _line warn "$_FORGE_CFG_FILE is not valid JSON — its forge settings were ignored"; fi
  if ! kind="$(forge_kind 2>/dev/null)"; then
    _line fail "FORGE / forge.kind holds an invalid value — use github, gitlab or none"; return 0
  fi
  forge_kind >/dev/null 2>&1; src="$_FORGE_SRC"
  url="$(_forge_remote_url)"
  host=""; [[ -n "$url" ]] && _forge_parse "$url" && host="$_P_HOST"
  _line ok "forge: $kind (from $src)${host:+, remote $(forge_remote) → $host}"
  case "$kind" in
    none)
      if [[ -n "$host" ]]; then
        _line warn "remote host $host is not a recognised forge — PRs are recorded as pr: local; declare it with FORGE=github|gitlab in ./.env or forge.kind in .agentic/config.json"
      else
        _line ok "no remote — PRs are recorded as pr: local"
      fi ;;
    github)
      if ! command -v gh >/dev/null 2>&1; then _line fail "gh not installed — the github forge needs it"
      elif gh auth status >/dev/null 2>&1; then _line ok "gh authenticated"
      else _line fail "gh is not authenticated — run: gh auth login"; fi ;;
    gitlab)
      if [[ -z "$(_forge_token)" ]]; then _line fail "no GitLab token — set FORGE_TOKEN or GITLAB_TOKEN in ./.env"; return 0; fi
      if ! _forge_token_ok "$(_forge_token)"; then _line fail "the GitLab token contains characters outside [A-Za-z0-9._~-] — check FORGE_TOKEN/GITLAB_TOKEN"; return 0; fi
      if ! base="$(_forge_gl_base 2>/dev/null)"; then
        if [[ -n "$(_forge_setting FORGE_URL)" ]]; then _line fail "FORGE_URL must start with https:// — the token is never sent over a scheme-less URL"
        else _line fail "cannot derive the GitLab URL — set FORGE_URL in ./.env"; fi
        return 0
      fi
      out=""
      if _forge_gl_api out GET "$base" /user 2>/dev/null; then
        _line ok "GitLab API authenticated as @$(jq -r '.username // "?"' <<<"$out" 2>/dev/null) ($base)"
      else
        case "$_GL_STATUS" in
          401|403) _line fail "GitLab rejected the token (HTTP $_GL_STATUS) at $base" ;;
          *)       _line warn "GitLab API unreachable or erroring (HTTP $_GL_STATUS) at $base — offline is not a failure" ;;
        esac
      fi ;;
  esac
  return 0
}

# --- CLI dispatch (skipped when sourced) --------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  cmd="${1:-}"; shift || true
  case "$cmd" in
    kind)      forge_kind ;;
    remote)    forge_remote; echo ;;
    push)      forge_push "$@" ;;
    pr-create) forge_pr_create "$@" ;;
    pr-state)  forge_pr_state "$@" ;;
    pr-close)  forge_pr_close "$@" ;;
    check)     forge_check ;;
    *) echo "usage: forge.sh kind|remote|push|pr-create|pr-state|pr-close|check ..." >&2; exit 2 ;;
  esac
fi
