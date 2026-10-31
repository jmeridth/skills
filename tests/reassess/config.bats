#!/usr/bin/env bats

load helpers

setup() {
  setup_stub
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

dump() {
  run "$SCRIPT" --dump-config --config "$CONFIG"
}

@test "valid config normalizes tilde and trailing slash" {
  write_config '
default_clone_path: ~/code/
monitor:
  - org: my-org
    exclude: [legacy, sandbox]
  - repo: other/one
    path: ~/work/one/
  - repo: other/two
'
  dump
  [ "$status" -eq 0 ]
  [ "$(jq -r .default_clone_path <<<"$output")" = "$HOME/code" ]
  [ "$(jq -c '.monitor[0]' <<<"$output")" = '{"kind":"org","org":"my-org","exclude":["legacy","sandbox"]}' ]
  [ "$(jq -c '.monitor[1]' <<<"$output")" = "{\"kind\":\"repo\",\"repo\":\"other/one\",\"path\":\"$HOME/work/one\"}" ]
  [ "$(jq -c '.monitor[2]' <<<"$output")" = '{"kind":"repo","repo":"other/two","path":null}' ]
}

@test "org entry without exclude gets an empty list" {
  write_config '
monitor:
  - org: my-org
'
  dump
  [ "$status" -eq 0 ]
  [ "$(jq -c '.monitor[0].exclude' <<<"$output")" = '[]' ]
  [ "$(jq -c .default_clone_path <<<"$output")" = 'null' ]
}

@test "missing file exits 2 and prints the schema" {
  CONFIG="$BATS_TEST_TMPDIR/nope.yaml"
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"monitor:"* ]]
}

@test "invalid yaml exits 2" {
  write_config 'monitor: [unclosed'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"monitor:"* ]]
}

@test "empty monitor exits 2" {
  write_config 'monitor: []'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"monitor:"* ]]
}

@test "entry with both org and repo exits 2" {
  write_config '
monitor:
  - org: o
    repo: o/r
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"monitor:"* ]]
}

@test "repo without slash exits 2" {
  write_config '
monitor:
  - repo: justname
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"monitor:"* ]]
}

@test "exclude must be a list of names" {
  write_config '
monitor:
  - org: o
    exclude: not-a-list
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"monitor:"* ]]
}

@test "yq that is not mikefarah v4 exits 2 with a message" {
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  printf '#!/bin/sh\necho "yq 3.4.1"\n' >"$BATS_TEST_TMPDIR/fakebin/yq"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/yq"
  PATH="$BATS_TEST_TMPDIR/fakebin:$PATH"
  write_config '
monitor:
  - org: o
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"mikefarah"* ]]
}
