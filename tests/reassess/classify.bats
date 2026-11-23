#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load helpers

setup() {
  setup_stub
  export REASSESS_NOW="2026-10-31T00:00:00Z"
}

# run_repo <owner/repo>: run single-repo mode, stdout only.
run_repo() {
  run --separate-stderr "$SCRIPT" "$1"
}

# pr <number> <author> [isDraft] [updatedAt]: add one PR to the o/r search fixture.
rows=()
pr() {
  rows+=("$(search_row o/r "$1" "$2" "${3:-false}" false "${4:-2026-10-30T00:00:00Z}")")
}
publish() {
  fixture search_prs__o_r "[$(
    IFS=,
    echo "${rows[*]}"
  )]"
}

# wait_of / reasons_of: the first row's maintainer_wait flag and joined reasons.
wait_of() { jq -r '.prs[0].maintainer_wait' <<<"$output"; }
reasons_of() { jq -r '.prs[0].reasons | join(" | ")' <<<"$output"; }

@test "bucket A when another person's comment is newer than my push" {
  pr 1 me
  publish
  view 1 "[$(c bob 2026-10-25T00:00:00Z)]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[]"
  run_repo o/r
  [ "$status" -eq 0 ]
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "A" ]
  [ "$(jq -r '.prs[0].raw.last_other_activity' <<<"$output")" = "2026-10-25T00:00:00Z" ]
  [ "$(jq -r '.prs[0].raw.my_last_activity' <<<"$output")" = "2026-10-20T00:00:00Z" ]
}

@test "no row when my reply is newer than their comment" {
  pr 1 me
  publish
  view 1 "[$(c bob 2026-10-25T00:00:00Z), $(c me 2026-10-26T00:00:00Z)]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 0 ]
}

@test "resolved thread does not count as new activity" {
  pr 1 me
  publish
  view 1 "[]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[$(th true bob 2026-10-25T00:00:00Z)]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 0 ]
}

@test "unresolved inline thread from another person puts my PR in A" {
  pr 1 me
  publish
  view 1 "[]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[$(th false bob 2026-10-25T00:00:00Z)]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "A" ]
}

@test "bot issue comment is ignored" {
  pr 1 me
  publish
  view 1 "[$(c 'dependabot[bot]' 2026-10-25T00:00:00Z)]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 0 ]
}

@test "bot review with inline comments is kept and noted" {
  pr 1 me
  publish
  view 1 "[]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[$(th false 'github-actions[bot]' 2026-10-25T00:00:00Z)]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "A" ]
  [[ "$(jq -r '.prs[0].reasons | join(" ")' <<<"$output")" == *"bot"* ]]
}

@test "bucket B when the head commit is newer than my review, approval noted" {
  pr 2 alice
  publish
  view 2 "[]" "[$(rv me 2026-10-20T00:00:00Z APPROVED)]" "[$(cm alice 2026-10-22T00:00:00Z)]"
  threads 2 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "B" ]
  [[ "$(jq -r '.prs[0].reasons | join(" ")' <<<"$output")" == *"previously approved"* ]]
}

@test "equal timestamps are not stale" {
  pr 2 alice
  publish
  view 2 "[]" "[$(rv me 2026-10-20T00:00:00Z COMMENTED)]" "[$(cm alice 2026-10-20T00:00:00Z)]"
  threads 2 "[]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 0 ]
}

@test "commenter-only candidate compares my comment time to the head commit" {
  pr 2 alice
  publish
  view 2 "[$(c me 2026-10-20T00:00:00Z)]" "[]" "[$(cm alice 2026-10-22T00:00:00Z)]"
  threads 2 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "B" ]
  [ "$(jq -r '.prs[0].raw.my_last_touch' <<<"$output")" = "2026-10-20T00:00:00Z" ]
}

@test "bucket C when I left no review or comment" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-28T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "C" ]
}

@test "a reviewed PR with no new commits is not C" {
  REASSESS_NOW="2026-10-21T00:00:00Z"
  pr 3 carol
  publish
  view 3 "[]" "[$(rv me 2026-10-20T00:00:00Z COMMENTED)]" "[$(cm carol 2026-10-19T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 0 ]
}

@test "my PR found by several searches yields one row in A" {
  pr 1 me
  publish
  view 1 "[$(c bob 2026-10-25T00:00:00Z)]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 1 "[]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 1 ]
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "A" ]
  [ "$(jq '.prs[0].roles | length' <<<"$output")" -eq 5 ]
}

@test "draft candidate on a failing required check" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-28T00:00:00Z)]"
  threads 3 "[]"
  checks 3 '[{"name":"build","bucket":"fail"},{"name":"lint","bucket":"pass"}]'
  run_repo o/r
  [ "$(jq -r '.prs[0].draft_candidate' <<<"$output")" = "true" ]
  [[ "$(jq -r '.prs[0].reasons | join(" ")' <<<"$output")" == *"build"* ]]
}

@test "failing checks are read even when gh pr checks exits non-zero" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-28T00:00:00Z)]"
  threads 3 "[]"
  checks 3 '[{"name":"build","bucket":"fail"}]'
  echo 1 >"$GH_STUB_DIR/pr_checks__3.exit"
  run_repo o/r
  [ "$(jq -r '.prs[0].draft_candidate' <<<"$output")" = "true" ]
}

@test "draft candidate when the author is silent for 7 days after my review" {
  pr 3 carol
  publish
  view 3 "[]" "[$(rv me 2026-10-20T00:00:00Z COMMENTED)]" "[$(cm carol 2026-10-19T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].draft_candidate' <<<"$output")" = "true" ]
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "null" ]
}

@test "no draft flag within 7 days of my review" {
  REASSESS_NOW="2026-10-25T00:00:00Z"
  pr 3 carol
  publish
  view 3 "[]" "[$(rv me 2026-10-20T00:00:00Z COMMENTED)]" "[$(cm carol 2026-10-19T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 0 ]
}

@test "no draft flag on my own PRs or my own drafts, and no checks call for them" {
  pr 1 me
  pr 4 me true
  publish
  local n
  for n in 1 4; do
    view "$n" "[$(c bob 2026-10-25T00:00:00Z)]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
    threads "$n" "[]"
  done
  checks 1 '[{"name":"build","bucket":"fail"}]'
  run_repo o/r
  [ "$(jq '.prs | length' <<<"$output")" -eq 2 ]
  [ "$(jq '[.prs[] | select(.draft_candidate)] | length' <<<"$output")" -eq 0 ]
  run ! grep -q "pr checks" "$GH_STUB_DIR/calls.log"
}

@test "required-checks error skips the flag and is noted" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-28T00:00:00Z)]"
  threads 3 "[]"
  : >"$GH_STUB_DIR/pr_checks__3.fail"
  run_repo o/r
  [ "$(jq -r '.prs[0].draft_candidate' <<<"$output")" = "false" ]
  [[ "$(jq -r '.prs[0].reasons | join(" ")' <<<"$output")" == *"unavailable"* ]]
}

@test "a branch with no required checks is not reported as unavailable" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-28T00:00:00Z)]"
  threads 3 "[]"
  echo "no required checks reported on the 'topic' branch" >"$GH_STUB_DIR/pr_checks__3.fail"
  run_repo o/r
  [ "$(jq -r '.prs[0].draft_candidate' <<<"$output")" = "false" ]
  [[ "$(jq -r '.prs[0].reasons | join(" ")' <<<"$output")" != *"unavailable"* ]]
}

@test "sorted by bucket then updatedAt, newest first" {
  pr 10 carol false 2026-10-29T00:00:00Z
  pr 11 carol false 2026-10-30T00:00:00Z
  pr 12 me false 2026-10-27T00:00:00Z
  pr 13 alice false 2026-10-26T00:00:00Z
  publish
  local n
  for n in 10 11; do
    view "$n" "[]" "[]" "[$(cm carol 2026-10-28T00:00:00Z)]"
    threads "$n" "[]"
  done
  view 12 "[$(c bob 2026-10-25T00:00:00Z)]" "[]" "[$(cm me 2026-10-20T00:00:00Z)]"
  threads 12 "[]"
  view 13 "[]" "[$(rv me 2026-10-20T00:00:00Z COMMENTED)]" "[$(cm alice 2026-10-22T00:00:00Z)]"
  threads 13 "[]"
  run_repo o/r
  [ "$(jq -c '[.prs[].number]' <<<"$output")" = "[12,13,11,10]" ]
}

@test "rate limit during detail fetch exits 3 with empty stdout" {
  pr 3 carol
  publish
  GH_STUB_FAIL_MATCH="pr view" run_repo o/r
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}

# Maintainer wait gate. NOW is 2026-10-31, so 7 days back is 2026-10-24.

@test "C waits when another maintainer commented within 7 days" {
  pr 3 carol
  publish
  view 3 "[$(c dave 2026-10-28T00:00:00Z MEMBER)]" "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "C" ]
  [ "$(wait_of)" = "true" ]
  [[ "$(reasons_of)" == *"waiting on author: dave engaged 3 days ago"* ]]
  [ "$(jq -r '.prs[0].raw.last_maintainer_activity' <<<"$output")" = "2026-10-28T00:00:00Z" ]
  [ "$(jq -r '.prs[0].raw.author_last_activity' <<<"$output")" = "2026-10-20T00:00:00Z" ]
}

@test "C does not wait after 7+ quiet days since the maintainer engaged" {
  pr 3 carol
  publish
  view 3 "[$(c dave 2026-10-20T00:00:00Z OWNER)]" "[]" "[$(cm carol 2026-10-19T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "C" ]
  [ "$(wait_of)" = "false" ]
  [[ "$(reasons_of)" == *"dave engaged 11 days ago; author quiet 7+ days"* ]]
}

@test "C waits when the author was active within 7 days after a maintainer engaged" {
  pr 3 carol
  publish
  view 3 "[$(c carol 2026-10-29T00:00:00Z)]" \
    "[$(rv dave 2026-10-10T00:00:00Z CHANGES_REQUESTED 'please split this' COLLABORATOR)]" \
    "[$(cm carol 2026-10-09T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(wait_of)" = "true" ]
  [[ "$(reasons_of)" == *"waiting on author: author active 2 days ago"* ]]
  [ "$(jq -r '.prs[0].raw.author_last_activity' <<<"$output")" = "2026-10-29T00:00:00Z" ]
}

@test "an inline thread from a maintainer counts as engagement" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[$(th false dave 2026-10-29T00:00:00Z COLLABORATOR)]"
  run_repo o/r
  [ "$(wait_of)" = "true" ]
}

@test "CONTRIBUTOR and NONE associations do not count as maintainers" {
  pr 3 carol
  publish
  view 3 "[$(c dave 2026-10-28T00:00:00Z CONTRIBUTOR), $(c erin 2026-10-29T00:00:00Z NONE)]" \
    "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(wait_of)" = "false" ]
  [ "$(jq -r '.prs[0].raw.last_maintainer_activity' <<<"$output")" = "null" ]
}

@test "a bot does not count as a maintainer, even with a MEMBER association" {
  pr 3 carol
  publish
  view 3 "[$(c 'github-actions[bot]' 2026-10-28T00:00:00Z MEMBER)]" "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[$(th false 'copilot[bot]' 2026-10-29T00:00:00Z MEMBER)]"
  run_repo o/r
  [ "$(wait_of)" = "false" ]
  [ "$(jq -r '.prs[0].raw.last_maintainer_activity' <<<"$output")" = "null" ]
}

@test "an empty COMMENTED review from a maintainer does not count" {
  pr 3 carol
  publish
  view 3 "[]" "[$(rv dave 2026-10-28T00:00:00Z COMMENTED '' MEMBER)]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(wait_of)" = "false" ]
}

@test "an approval from another maintainer does not gate" {
  pr 3 carol
  publish
  view 3 "[]" "[$(rv dave 2026-10-29T00:00:00Z APPROVED 'lgtm' MEMBER)]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(wait_of)" = "false" ]
  [ "$(jq -r '.prs[0].raw.last_maintainer_activity' <<<"$output")" = "null" ]
}

@test "a resolved inline thread from a maintainer does not gate" {
  pr 3 carol
  publish
  view 3 "[]" "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[$(th true dave 2026-10-29T00:00:00Z MEMBER)]"
  run_repo o/r
  [ "$(wait_of)" = "false" ]
  [ "$(jq -r '.prs[0].raw.last_maintainer_activity' <<<"$output")" = "null" ]
}

@test "B is not gated but notes the other maintainer" {
  pr 2 alice
  publish
  view 2 "[$(c dave 2026-10-29T00:00:00Z MEMBER)]" "[$(rv me 2026-10-20T00:00:00Z COMMENTED)]" \
    "[$(cm alice 2026-10-22T00:00:00Z)]"
  threads 2 "[]"
  run_repo o/r
  [ "$(jq -r '.prs[0].bucket' <<<"$output")" = "B" ]
  [ "$(wait_of)" = "false" ]
  [[ "$(reasons_of)" == *"maintainer dave also engaged 2 days ago"* ]]
}

@test "review request plus a maintainer @-mention overrides the wait" {
  pr 3 carol
  publish
  view 3 "[$(c dave 2026-10-29T00:00:00Z MEMBER '@ME can you take a look?')]" "[]" \
    "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq -c '.prs[0].roles | index("review-requested") != null' <<<"$output")" = "true" ]
  [ "$(wait_of)" = "false" ]
  [[ "$(reasons_of)" == *"review explicitly requested by dave"* ]]
}

@test "an @-mention without a review request still waits" {
  pr 3 carol
  publish
  # Role searches pass my login first, so this fixture empties them; only the open search finds the PR.
  fixture search_prs__me "[]"
  view 3 "[$(c dave 2026-10-29T00:00:00Z MEMBER '@me can you take a look?')]" "[]" \
    "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(jq -c '.prs[0].roles' <<<"$output")" = '["open"]' ]
  [ "$(wait_of)" = "true" ]
}

@test "a review request without an @-mention still waits" {
  pr 3 carol
  publish
  view 3 "[$(c dave 2026-10-29T00:00:00Z MEMBER '@meow please look')]" "[]" \
    "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(wait_of)" = "true" ]
}

@test "exactly 7 days of quiet ends the wait; one second less does not" {
  pr 3 carol
  publish
  view 3 "[$(c dave 2026-10-24T00:00:00Z MEMBER)]" "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  threads 3 "[]"
  run_repo o/r
  [ "$(wait_of)" = "false" ]
  view 3 "[$(c dave 2026-10-24T00:00:01Z MEMBER)]" "[]" "[$(cm carol 2026-10-20T00:00:00Z)]"
  run_repo o/r
  [ "$(wait_of)" = "true" ]
}
