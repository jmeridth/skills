# Shared bats helpers for the reassess-candidates tests.
# shellcheck disable=SC2034 # SCRIPT and CONFIG are used by the bats files that load this helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
SCRIPT="$REPO_ROOT/jmeridth-skills/skills/reassess/scripts/reassess-candidates"

# Put the stub gh first on PATH and give the test its own fixture directory.
setup_stub() {
  export GH_STUB_DIR="$BATS_TEST_TMPDIR/gh"
  mkdir -p "$GH_STUB_DIR"
  : >"$GH_STUB_DIR/calls.log"
  echo "me" >"$GH_STUB_DIR/user"
  export PATH="$BATS_TEST_DIRNAME/bin:$PATH"
}

# write_config <yaml-text>: write the text to $BATS_TEST_TMPDIR/config.yaml.
write_config() {
  printf '%s\n' "$1" >"$BATS_TEST_TMPDIR/config.yaml"
  CONFIG="$BATS_TEST_TMPDIR/config.yaml"
}

# fixture <name> <json>: set the stub's answer for gh calls keyed <name>.
fixture() {
  printf '%s\n' "$2" >"$GH_STUB_DIR/$1.json"
}

# search_row <repo> <number> <author> [isDraft] [archived]: one gh search row.
search_row() {
  jq -cn --arg repo "$1" --argjson n "$2" --arg author "$3" \
    --argjson draft "${4:-false}" --argjson archived "${5:-false}" \
    --arg updated "${6:-2026-10-30T00:00:00Z}" '{
      repository: {nameWithOwner: $repo, name: ($repo | split("/")[1]), isArchived: $archived},
      number: $n, title: ("PR " + ($n | tostring)), author: {login: $author},
      isDraft: $draft, updatedAt: $updated
    }'
}

# Event builders for classification tests. Timestamps are plain strings.
# c <login> <ts>: issue comment. rv <login> <ts> <state> [body]: review.
# cm <login> <ts>: commit. th <resolved> <login> <ts>: review thread, one comment.
c() { jq -cn --arg l "$1" --arg t "$2" '{author: {login: $l}, createdAt: $t, body: "x"}'; }
rv() { jq -cn --arg l "$1" --arg t "$2" --arg s "$3" --arg b "${4:-looks good}" '{author: {login: $l}, submittedAt: $t, state: $s, body: $b}'; }
cm() { jq -cn --arg l "$1" --arg t "$2" '{committedDate: $t, authors: [{login: $l}]}'; }
th() { jq -cn --argjson r "$1" --arg l "$2" --arg t "$3" '{isResolved: $r, comments: {nodes: [{author: {login: $l}, createdAt: $t}]}}'; }

# view <n> <comments...>: write pr_view__<n>.json from three JSON arrays.
view() {
  jq -cn --argjson c "$2" --argjson r "$3" --argjson m "$4" '{comments: $c, reviews: $r, commits: $m}' \
    >"$GH_STUB_DIR/pr_view__$1.json"
}
threads() {
  jq -cn --argjson n "$2" '{data: {repository: {pullRequest: {reviewThreads: {nodes: $n}}}}}' \
    >"$GH_STUB_DIR/api_graphql__number_$1.json"
}
checks() { fixture "pr_checks__$1" "$2"; }
