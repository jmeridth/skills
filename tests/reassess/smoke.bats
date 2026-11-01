#!/usr/bin/env bats

load helpers

@test "script prints usage with --help" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "script with no args exits 1" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}
