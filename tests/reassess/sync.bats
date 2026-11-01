#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_stub
  export REASSESS_NOW="2026-10-31T00:00:00Z"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # Keep the user's signing config and hooks out of the fixture repos.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

  ORIGIN="$BATS_TEST_TMPDIR/remotes/o/r.git"
  SEED="$BATS_TEST_TMPDIR/seed"
  CLONE="$BATS_TEST_TMPDIR/code/r"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$SEED"
  git -C "$SEED" remote add origin "$ORIGIN"
  echo one >"$SEED/f"
  git -C "$SEED" add f
  git -C "$SEED" commit -q -m one
  git -C "$SEED" push -q origin main
  mkdir -p "$BATS_TEST_TMPDIR/code"
  git clone -q "$ORIGIN" "$CLONE"

  fixture search_prs__o_r "[$(search_row o/r 1 alice)]"
  write_config "
default_clone_path: $BATS_TEST_TMPDIR/code
monitor:
  - repo: o/r
"
}

remote_commit() {
  echo "$1" >>"$SEED/f"
  git -C "$SEED" commit -q -am "$1"
  git -C "$SEED" push -q origin main
}

refresh() {
  run --separate-stderr "$SCRIPT" --config "$CONFIG"
}

sync_field() {
  jq -r ".sync[0].$1" <<<"$output"
}

@test "clean default branch fast-forwards" {
  remote_commit two
  refresh
  [ "$status" -eq 0 ]
  [ "$(sync_field status)" = "synced" ]
  [ "$(jq -r '.prs[0].clone_path' <<<"$output")" = "$CLONE" ]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$(git -C "$SEED" rev-parse HEAD)" ]
}

@test "missing clone is skipped with a reason" {
  rm -rf "$CLONE"
  refresh
  [ "$status" -eq 0 ]
  [ "$(sync_field status)" = "skipped" ]
  [ "$(sync_field reason)" = "no clone" ]
  [ "$(jq -r '.prs[0].clone_path' <<<"$output")" = "null" ]
}

@test "dirty tree is skipped and left untouched" {
  remote_commit two
  echo scratch >>"$CLONE/f"
  before=$(git -C "$CLONE" rev-parse HEAD)
  refresh
  [ "$(sync_field status)" = "skipped" ]
  [ "$(sync_field reason)" = "dirty tree" ]
  [ "$(git -C "$CLONE" rev-parse HEAD)" = "$before" ]
  [ "$(tail -n1 "$CLONE/f")" = "scratch" ]
}

@test "non-default branch is skipped and not switched" {
  git -C "$CLONE" checkout -q -b topic
  remote_commit two
  refresh
  [ "$(sync_field reason)" = "not on default branch" ]
  [ "$(git -C "$CLONE" branch --show-current)" = "topic" ]
}

@test "diverged branch is skipped" {
  echo local >>"$CLONE/f"
  git -C "$CLONE" commit -q -am local
  remote_commit two
  refresh
  [ "$(sync_field reason)" = "diverged" ]
}

@test "path override beats default_clone_path" {
  mv "$CLONE" "$BATS_TEST_TMPDIR/elsewhere"
  write_config "
default_clone_path: $BATS_TEST_TMPDIR/code
monitor:
  - repo: o/r
    path: $BATS_TEST_TMPDIR/elsewhere
"
  remote_commit two
  refresh
  [ "$(sync_field status)" = "synced" ]
  [ "$(git -C "$BATS_TEST_TMPDIR/elsewhere" rev-parse HEAD)" = "$(git -C "$SEED" rev-parse HEAD)" ]
}

@test "falls back to gh for the default branch" {
  git -C "$CLONE" remote set-head origin -d
  echo main >"$GH_STUB_DIR/repo_view.json"
  remote_commit two
  refresh
  [ "$(sync_field status)" = "synced" ]
}

@test "single-repo mode syncs the current directory when it is a clone" {
  remote_commit two
  cd "$CLONE"
  run --separate-stderr "$SCRIPT" o/r
  [ "$(sync_field status)" = "synced" ]
}

@test "single-repo mode outside a clone is skipped" {
  cd "$BATS_TEST_TMPDIR"
  run --separate-stderr "$SCRIPT" o/r
  [ "$(sync_field status)" = "skipped" ]
  [ "$(sync_field reason)" = "no clone" ]
}
