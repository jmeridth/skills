# Shared bats helpers for the reassess-candidates tests.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
# shellcheck disable=SC2034 # used by the bats files that load this helper
SCRIPT="$REPO_ROOT/jmeridth-skills/skills/reassess/scripts/reassess-candidates"

# Put the stub gh first on PATH and give the test its own fixture directory.
setup_stub() {
  export GH_STUB_DIR="$BATS_TEST_TMPDIR/gh"
  mkdir -p "$GH_STUB_DIR"
  : >"$GH_STUB_DIR/calls.log"
  echo "me" >"$GH_STUB_DIR/user"
  export PATH="$BATS_TEST_DIRNAME/bin:$PATH"
}
