# bench-repo.sh — shared git fixture for evals/cases/bench/*.
# Sourced (not executed) by a bash-unit case's $cmd; cwd is the eval's
# mktemp sandbox when bench_fixture_setup is called.
#
# bench_fixture_setup [--conflict]
#   Builds origin/ (bare, default branch main) and work/ (a clone — the repo
#   bench.sh operates from, left checked out on main). A "feature" branch
#   exists and is pushed to origin.
#     plain (default): main has f.txt (base); feature adds f2.txt — the
#       freshness merge is clean.
#     --conflict: main and feature both rewrite f.txt — the freshness merge
#       conflicts.
bench_fixture_setup() {
  local mode="${1:-}" root="$PWD"
  mkdir -p origin && (cd origin && git init -q --bare)
  mkdir -p seed
  (
    cd seed
    git init -q -b main
    git config user.email t@t.com
    git config user.name t
    echo base > f.txt
    git add f.txt
    git commit -q -m base
    git remote add origin "$root/origin"
    git push -q origin main
  )
  git -C origin symbolic-ref HEAD refs/heads/main
  git clone -q "$root/origin" work
  (
    cd work
    git config user.email t@t.com
    git config user.name t
    git checkout -q -b feature
    if [[ "$mode" == "--conflict" ]]; then
      echo feature-v2 > f.txt
    else
      echo feature > f2.txt
    fi
    git add -A
    git commit -q -m feature
    git push -q origin feature
    git checkout -q main
    if [[ "$mode" == "--conflict" ]]; then
      echo main-v2 > f.txt
      git add -A
      git commit -q -m main-v2
      git push -q origin main
    fi
  )
}

# bench_fixture_spec DIR STATUS BRANCH ID — write one factory/specs frontmatter file.
bench_fixture_spec() {
  local dir="$1" status="$2" branch="$3" id="$4"
  mkdir -p "$dir/factory/specs"
  printf -- '---\nid: %s\ntitle: t\nstatus: %s\nbranch: %s\n---\nbody\n' \
    "$id" "$status" "$branch" > "$dir/factory/specs/${id}-t.md"
}
