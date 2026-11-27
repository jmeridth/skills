#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_stub
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export REASSESS_NOW="2026-11-26T12:00:00Z"
}

single() {
  run --separate-stderr "$SCRIPT" o/r
}

# closed_row <repo> <number> <author> [updatedAt]: one closed-state search row.
closed_row() {
  jq -cn --arg repo "$1" --argjson n "$2" --arg author "$3" --arg updated "${4:-2026-11-25T00:00:00Z}" '{
    repository: {nameWithOwner: $repo, name: ($repo | split("/")[1]), isArchived: false},
    number: $n, title: ("PR " + ($n | tostring)), author: {login: $author},
    isDraft: false, updatedAt: $updated
  }'
}

# closed_view <n> <state> <closedAt> [mergedBy]: pr view detail for a closed PR.
closed_view() {
  jq -cn --arg s "$2" --arg c "$3" --arg by "${4:-}" '{
    state: $s, closedAt: $c,
    mergedAt: (if $s == "MERGED" then $c else null end),
    mergedBy: (if $by == "" then null else {login: $by} end)
  }' >"$GH_STUB_DIR/pr_view__$1.json"
}

@test "single-repo mode searches closed PRs I reviewed or commented on in the last 3 days" {
  run --separate-stderr "$SCRIPT" --dump-queries o/r
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.[] | select(.state == "closed") | .role] | sort' <<<"$output")" = '["commenter","reviewed-by"]' ]
  [ "$(jq '[.[] | select(.state == "closed") | .args | select(index("--closed") != null and index(">=2026-11-23T12:00:00Z") != null and index("closed") != null)] | length' <<<"$output")" -eq 2 ]
}

@test "--closed-since sets the window in hours" {
  run --separate-stderr "$SCRIPT" --dump-queries --closed-since 24h o/r
  [ "$status" -eq 0 ]
  [ "$(jq '[.[] | select(.state == "closed") | .args | select(index(">=2026-11-25T12:00:00Z") != null)] | length' <<<"$output")" -eq 2 ]
}

@test "--closed-since rejects a malformed window" {
  run --separate-stderr "$SCRIPT" --closed-since 3w o/r
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"--closed-since expects a window like 3d or 24h"* ]]
}

@test "reports a merged PR with who merged it" {
  fixture search_prs__closed "[$(closed_row o/r 12 alice)]"
  closed_view 12 MERGED 2026-11-25T10:00:00Z bob
  single
  [ "$status" -eq 0 ]
  [ "$(jq -c '.closed[0] | {repo, number, author, state, closedAt, mergedBy}' <<<"$output")" = '{"repo":"o/r","number":12,"author":"alice","state":"MERGED","closedAt":"2026-11-25T10:00:00Z","mergedBy":"bob"}' ]
}

@test "reports a PR closed without merging" {
  fixture search_prs__closed "[$(closed_row o/r 13 alice)]"
  closed_view 13 CLOSED 2026-11-25T11:00:00Z
  single
  [ "$(jq -c '.closed[0] | {state, mergedBy}' <<<"$output")" = '{"state":"CLOSED","mergedBy":null}' ]
}

@test "drops a PR that was reopened after closing" {
  fixture search_prs__closed "[$(closed_row o/r 14 alice)]"
  closed_view 14 OPEN 2026-11-25T11:00:00Z
  single
  [ "$(jq -c '.closed' <<<"$output")" = '[]' ]
}

@test "a PR found by both roles appears once with both roles" {
  fixture search_prs__closed "[$(closed_row o/r 15 alice)]"
  closed_view 15 MERGED 2026-11-25T10:00:00Z bob
  single
  [ "$(jq '.closed | length' <<<"$output")" -eq 1 ]
  [ "$(jq -c '.closed[0].roles' <<<"$output")" = '["commenter","reviewed-by"]' ]
}

@test "lists the most recently closed first" {
  fixture search_prs__closed "[$(closed_row o/r 16 alice), $(closed_row o/r 17 alice)]"
  closed_view 16 MERGED 2026-11-24T10:00:00Z bob
  closed_view 17 MERGED 2026-11-25T10:00:00Z bob
  single
  [ "$(jq -c '[.closed[].number]' <<<"$output")" = '[17,16]' ]
}

@test "closed PRs never become report rows" {
  fixture search_prs__closed "[$(closed_row o/r 18 alice)]"
  closed_view 18 MERGED 2026-11-25T10:00:00Z bob
  single
  [ "$(jq -c '[.closed[].number]' <<<"$output")" = '[18]' ]
  [ "$(jq -c '.prs' <<<"$output")" = '[]' ]
}

@test "no closed PRs gives an empty list" {
  single
  [ "$status" -eq 0 ]
  [ "$(jq -c '.closed' <<<"$output")" = '[]' ]
}

@test "refresh mode searches closed PRs per org" {
  write_config '
monitor:
  - org: my-org
'
  run --separate-stderr "$SCRIPT" --dump-queries --config "$CONFIG"
  [ "$(jq '[.[] | select(.state == "closed") | .args | select(index("--owner") != null and index("my-org") != null)] | length' <<<"$output")" -eq 2 ]
}

@test "1000 closed results marks the closed query truncated" {
  jq -cn '[range(1000) | {repository: {nameWithOwner: "o/r", name: "r", isArchived: true}, number: ., title: "t", author: {login: "alice"}, isDraft: false, updatedAt: "2026-11-25T00:00:00Z"}]' \
    >"$GH_STUB_DIR/search_prs__closed.json"
  single
  [ "$status" -eq 0 ]
  [ "$(jq '[.truncated[] | select(.query | startswith("closed "))] | length' <<<"$output")" -ge 1 ]
}

@test "rate limit on a closed PR lookup exits 3 with empty stdout" {
  fixture search_prs__closed "[$(closed_row o/r 19 alice)]"
  GH_STUB_FAIL_MATCH="pr view 19" single
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}
