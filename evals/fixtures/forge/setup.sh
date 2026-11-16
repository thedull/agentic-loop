# setup.sh — shared helpers for evals/cases/forge/*. Sourced (not executed) by
# a bash-unit case's $cmd; cwd is the eval's mktemp sandbox.
#
# Mock files (all under $FORGE_MOCK_DIR):
#   http/<key>   first line `status: NNN` or `transport-error`, rest = body.
#                <key> = "<METHOD> <path+query>" with non-alphanumerics -> _
#   gh/<key>     first line `exit: N`, rest = stdout. <key> = first two argv
#                words joined by _ (pr_view, pr_list, pr_create, pr_close,
#                auth_status)
#   calls.log    one line per curl/gh/git-push invocation: tool TAB argv(US-sep)
#   requests.log one line per curl request: METHOD URL auth=.. data=..
#   git-push.log one line per intercepted `git push`
# The shims never log stdin or any GIT_CONFIG value.

F="$PLUGIN_ROOT/scripts/lib/forge.sh"
export PATH="$FIXTURES/forge/bin:$PATH"
FX_MISSING=0
FX_US=$'\x1f'

fx_init() {
  export FORGE_MOCK_DIR="$PWD/.mock" TMPDIR="$PWD/.tmp" HOME="$PWD/.home"
  mkdir -p "$FORGE_MOCK_DIR/http" "$FORGE_MOCK_DIR/gh" "$TMPDIR" "$HOME"
  unset FORGE FORGE_URL FORGE_REMOTE FORGE_TOKEN GITLAB_TOKEN \
        GIT_CONFIG_COUNT FORGE_MOCK_EXPECT_TOKEN
  git init -q -b main .
  git config user.email t@example.test
  git config user.name test
  git commit -q --allow-empty -m init
  printf 'body line one\nbody line two\n' > body.md
  touch .marker
}

# fx_remote URL [NAME]
fx_remote() { git remote add "${2:-origin}" "$1"; }
fx_setremote() { git remote set-url "${2:-origin}" "$1"; }

# fx_http "METHOD /path?query" STATUS|transport-error [BODY]
fx_http() {
  local f; f="$FORGE_MOCK_DIR/http/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"
  if [[ "$2" == transport-error ]]; then echo transport-error > "$f"
  else printf 'status: %s\n%s\n' "$2" "${3:-}" > "$f"; fi
}
fx_http_clear() { rm -f "$FORGE_MOCK_DIR"/http/*; }

# fx_gh KEY EXIT [STDOUT]
fx_gh() { printf 'exit: %s\n%s\n' "$2" "${3:-}" > "$FORGE_MOCK_DIR/gh/$1"; }

fx_config() { mkdir -p .agentic; printf '%s\n' "$1" > .agentic/config.json; }

# fx_run ARGS... -> FX_OUT FX_ERR FX_RC. A missing forge.sh is rc 127 and makes
# fx_done exit 127, so every case fails against a tree without forge.sh.
fx_run() {
  if [[ ! -x "$F" ]]; then
    FX_OUT=""; FX_ERR="forge.sh missing"; FX_RC=127; FX_MISSING=127; return 0
  fi
  FX_OUT="$("$F" "$@" 2>"$PWD/.fx_err" </dev/null)"; FX_RC=$?
  FX_ERR="$(cat "$PWD/.fx_err")"
  return 0
}
fx_done() { exit "$FX_MISSING"; }

# fx_show LABEL -> LABEL.out=[..] LABEL.rc=N LABEL.nz=yes|no LABEL.err=[..]
fx_show() {
  local nz=no
  [[ $FX_RC -ne 0 && $FX_RC -ne 127 ]] && nz=yes
  printf '%s.out=[%s]\n%s.rc=%s\n%s.nz=%s\n%s.err=[%s]\n' \
    "$1" "$FX_OUT" "$1" "$FX_RC" "$1" "$nz" "$1" "$(printf '%s' "$FX_ERR" | tr '\n' ' ')"
}

fx_nreq() { if [[ -f "$FORGE_MOCK_DIR/requests.log" ]]; then wc -l < "$FORGE_MOCK_DIR/requests.log" | tr -d ' '; else echo 0; fi; }
fx_ncalls() { if [[ -f "$FORGE_MOCK_DIR/calls.log" ]]; then wc -l < "$FORGE_MOCK_DIR/calls.log" | tr -d ' '; else echo 0; fi; }
fx_reqs() { cat "$FORGE_MOCK_DIR/requests.log" 2>/dev/null; }
fx_reqs_clear() { rm -f "$FORGE_MOCK_DIR/requests.log" "$FORGE_MOCK_DIR/calls.log" "$FORGE_MOCK_DIR/git-push.log" "$FORGE_MOCK_DIR/token-match.log"; }
# fx_count TOOL WORD1 [WORD2]: calls whose first argv words match
fx_count() {
  [[ -f "$FORGE_MOCK_DIR/calls.log" ]] || { echo 0; return; }
  awk -F'\t' -v t="$1" -v w1="$2" -v w2="${3:-}" -v s="$FX_US" \
    '$1==t { n=split($2,a,s); if (a[1]==w1 && (w2=="" || a[2]==w2)) c++ } END { print c+0 }' \
    "$FORGE_MOCK_DIR/calls.log"
}
# calls.log with the unit separator rendered as a space
fx_calls_text() { tr "$FX_US" ' ' < "$FORGE_MOCK_DIR/calls.log" 2>/dev/null; }

# fx_tokscan TOKEN: token must be in no argv log and no file created or changed
# in the sandbox, TMPDIR or /tmp (the sandbox's own .env is the user's input).
fx_tokscan() {
  local tok="$1" leaks=""
  if grep -qF -- "$tok" "$FORGE_MOCK_DIR/calls.log" "$FORGE_MOCK_DIR/requests.log" 2>/dev/null; then leaks="argv-log"; fi
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ "$f" == "$PWD/.env" ]] && continue
    grep -qF -- "$tok" "$f" 2>/dev/null && leaks="$leaks $f"
  done < <( { find "$PWD" -type f -not -path "$PWD/.git/*" 2>/dev/null
              find "$TMPDIR" -type f 2>/dev/null
              find /tmp/ -maxdepth 3 -type f -newer "$PWD/.marker" 2>/dev/null; } | sort -u )
  if [[ -z "$leaks" ]]; then echo "tokscan=clean"; else echo "tokscan=LEAK:$leaks"; fi
}

# fx_nogh: PATH with every tool except gh (curl/git stay the shims).
fx_nogh() {
  local dir="$PWD/.nogh" d f b
  mkdir -p "$dir"
  local IFS=:
  for d in $PATH; do
    [[ -d "$d" && "$d" != "$FIXTURES/forge/bin" ]] || continue
    for f in "$d"/*; do
      b="${f##*/}"
      case "$b" in gh|curl|git) continue ;; esac
      [[ -x "$f" && ! -e "$dir/$b" ]] && ln -s "$f" "$dir/$b"
    done
  done
  cp "$FIXTURES/forge/bin/curl" "$FIXTURES/forge/bin/git" "$dir/"
  PATH="$dir"
}

# fx_doctor: run doctor.sh, set FX_SEC to the lines of the `forge:` section.
fx_doctor() {
  [[ -x "$F" ]] || FX_MISSING=127
  bash "$PLUGIN_ROOT/scripts/doctor.sh" > "$PWD/.doctor.out" 2>/dev/null </dev/null
  FX_SEC="$(awk '/^forge:/ {f=1; next} f && (/^[^ ]/ || NF==0) {exit} f' "$PWD/.doctor.out")"
}

# fx_nmeth METHOD: number of logged requests with that HTTP method
fx_nmeth() { local n; n="$(grep -c "^$1 " "$FORGE_MOCK_DIR/requests.log" 2>/dev/null)"; echo "${n:-0}"; }
# fx_has FILE NEEDLE LABEL: prints LABEL=yes|no (literal, case-sensitive)
fx_has() { if grep -qF -- "$2" "$1" 2>/dev/null; then echo "$3=yes"; else echo "$3=no"; fi; }

# fx_sec_count ERE: number of FX_SEC lines matching; fx_sec_has LABEL ERE
fx_sec_count() { printf '%s\n' "$FX_SEC" | grep -Ec -- "$1"; }
fx_sec_has() { if [[ "$(fx_sec_count "$2")" -ge 1 ]]; then echo "$1=yes"; else echo "$1=no"; fi; }
