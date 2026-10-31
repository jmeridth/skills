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
