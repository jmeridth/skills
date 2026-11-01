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
    --argjson draft "${4:-false}" --argjson archived "${5:-false}" '{
      repository: {nameWithOwner: $repo, name: ($repo | split("/")[1]), isArchived: $archived},
      number: $n, title: ("PR " + ($n | tostring)), author: {login: $author},
      isDraft: $draft, updatedAt: "2026-10-30T00:00:00Z"
    }'
}
