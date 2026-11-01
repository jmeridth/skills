#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_stub
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

queries() {
  run "$SCRIPT" --dump-queries --config "$CONFIG"
}

prs() {
  run --separate-stderr "$SCRIPT" --config "$CONFIG"
}

@test "org entry builds four queries with the org qualifier" {
  write_config '
monitor:
  - org: my-org
'
  queries
  [ "$status" -eq 0 ]
  [ "$(jq length <<<"$output")" -eq 4 ]
  [ "$(jq -r '[.[].role] | sort | join(",")' <<<"$output")" = "author,commenter,review-requested,reviewed-by" ]
  [ "$(jq '[.[] | select(.args | index("--owner") != null and index("my-org") != null)] | length' <<<"$output")" -eq 4 ]
}

@test "repo entries chunk at ten repos per query" {
  local entries="" i
  for i in $(seq 1 12); do entries+="  - repo: o/r$i"$'\n'; done
  write_config "monitor:
$entries"
  queries
  [ "$status" -eq 0 ]
  [ "$(jq length <<<"$output")" -eq 8 ]
  [ "$(jq '[.[] | select(.role == "author") | [.args[] | select(. == "--repo")] | length] | sort | join(",")' <<<"$output")" = '"2,10"' ]
}

@test "queries are open-only and exclude archived repos" {
  write_config '
monitor:
  - org: my-org
  - repo: o/r
'
  queries
  [ "$status" -eq 0 ]
  [ "$(jq '[.[] | select(.args | index("--archived=false") != null and index("--state") != null and index("open") != null)] | length' <<<"$output")" -eq 8 ]
}

@test "queries use the authenticated login for every role" {
  echo "jmeridth" >"$GH_STUB_DIR/user"
  write_config '
monitor:
  - org: my-org
'
  queries
  [ "$(jq '[.[] | select(.args | index("jmeridth") != null)] | length' <<<"$output")" -eq 4 ]
}

@test "org exclude drops the repo" {
  write_config '
monitor:
  - org: my-org
    exclude: [legacy]
'
  fixture search_prs__my_org "[$(search_row my-org/legacy 1 alice), $(search_row my-org/keep 2 alice)]"
  prs
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.prs[].repo]' <<<"$output")" = '["my-org/keep"]' ]
}

@test "explicit repo entry beats org exclude" {
  write_config '
monitor:
  - org: my-org
    exclude: [legacy]
  - repo: my-org/legacy
'
  fixture search_prs__my_org "[$(search_row my-org/legacy 1 alice)]"
  fixture search_prs__my_org_legacy "[$(search_row my-org/legacy 1 alice)]"
  prs
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.prs[].repo]' <<<"$output")" = '["my-org/legacy"]' ]
}

@test "dedupes mixed-case repo names" {
  write_config '
monitor:
  - org: my-org
'
  fixture search_prs__my_org "[$(search_row My-Org/Repo 1 alice), $(search_row my-org/repo 1 alice)]"
  prs
  [ "$status" -eq 0 ]
  [ "$(jq '.prs | length' <<<"$output")" -eq 1 ]
}

@test "drops archived repos reported by the search" {
  write_config '
monitor:
  - org: my-org
'
  fixture search_prs__my_org "[$(search_row my-org/old 1 alice false true), $(search_row my-org/live 2 alice)]"
  prs
  [ "$(jq -c '[.prs[].repo]' <<<"$output")" = '["my-org/live"]' ]
}

@test "drops drafts by others but keeps my own drafts" {
  write_config '
monitor:
  - org: my-org
'
  fixture search_prs__my_org "[$(search_row my-org/r 1 alice true), $(search_row my-org/r 2 me true), $(search_row my-org/r 3 alice false)]"
  prs
  [ "$(jq -c '[.prs[].number] | sort' <<<"$output")" = '[2,3]' ]
}

@test "zero results gives empty prs and exit 0" {
  write_config '
monitor:
  - org: my-org
'
  prs
  [ "$status" -eq 0 ]
  [ "$(jq -c '.prs' <<<"$output")" = '[]' ]
  [ "$(jq -c '.truncated' <<<"$output")" = '[]' ]
}

@test "1000 results marks the query truncated" {
  write_config '
monitor:
  - org: my-org
'
  jq -cn '[range(1000) | {repository: {nameWithOwner: "my-org/r", name: "r"}, number: ., title: "t", author: {login: "alice"}, isDraft: false, updatedAt: "2026-10-30T00:00:00Z"}]' \
    >"$GH_STUB_DIR/search_prs__my_org.json"
  prs
  [ "$status" -eq 0 ]
  [ "$(jq '.truncated | length' <<<"$output")" -ge 1 ]
}

@test "rate limit exits 3 with empty stdout" {
  write_config '
monitor:
  - org: my-org
'
  GH_STUB_FAIL_MATCH="search prs" prs
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}

@test "unauthenticated gh exits 4 before any search" {
  write_config '
monitor:
  - org: my-org
'
  GH_STUB_UNAUTH=1 prs
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"gh auth login"* ]]
  run ! grep -q "search prs" "$GH_STUB_DIR/calls.log"
}

@test "single-repo mode needs no config and no yq" {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/bin/sh\nexit 99\n' >"$BATS_TEST_TMPDIR/fakebin/yq"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/yq"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
  fixture search_prs__o_r "[$(search_row o/r 7 alice)]"
  run --separate-stderr "$SCRIPT" o/r
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.prs[].number]' <<<"$output")" = '[7]' ]
}
