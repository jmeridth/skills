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

@test "tilde alone expands to home" {
  write_config '
default_clone_path: "~"
monitor:
  - org: o
'
  dump
  [ "$status" -eq 0 ]
  [ "$(jq -r .default_clone_path <<<"$output")" = "$HOME" ]
}

@test "other-user tilde path exits 2" {
  write_config '
default_clone_path: ~bob/code
monitor:
  - org: o
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"absolute"* ]]
}

@test "root path exits 2" {
  write_config '
default_clone_path: /
monitor:
  - org: o
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"/"* ]]
  [[ "$output" == *"root"* ]]
}

@test "relative path exits 2" {
  write_config '
monitor:
  - repo: o/r
    path: code/r
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"absolute"* ]]
}

@test "a string entry gets a clear error, not a jq message" {
  write_config '
monitor:
  - my-org
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"mapping"* ]]
  [[ "$output" != *"Cannot"* ]]
}

@test "a non-string path gets a clear error" {
  write_config '
monitor:
  - repo: o/r
    path: 5
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"path must be a string"* ]]
}

@test "a non-string default_clone_path gets a clear error" {
  write_config '
default_clone_path: [a, b]
monitor:
  - org: o
'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"default_clone_path must be a string"* ]]
}

@test "a config that is a list gets a clear error" {
  write_config '- org: o'
  dump
  [ "$status" -eq 2 ]
  [[ "$output" == *"mapping"* ]]
  [[ "$output" != *"Cannot"* ]]
}
