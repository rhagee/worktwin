#!/usr/bin/env bats

load test_helper

setup_config() {
  export WORKTWIN_LIGHT_BASES_FILE="$TEST_BASE/light-bases-test.json"
}

@test "path subcommand prints the config file path" {
  setup_config
  run "$BIN_DIR/worktwin-light-base" path
  [ "$status" -eq 0 ]
  [ "$output" = "$WORKTWIN_LIGHT_BASES_FILE" ]
}

@test "list is empty before any set" {
  if ! command -v jq >/dev/null 2>&1; then skip "jq required"; fi
  setup_config
  run "$BIN_DIR/worktwin-light-base" list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "set then get returns the mapping" {
  if ! command -v jq >/dev/null 2>&1; then skip "jq required"; fi
  setup_config
  mkdir -p "$TEST_BASE/base-target"
  "$BIN_DIR/worktwin-light-base" set "$TEST_REPO" "$TEST_BASE/base-target" >/dev/null
  run "$BIN_DIR/worktwin-light-base" get "$TEST_REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_BASE/base-target"* ]]
}

@test "get returns non-zero when mapping is absent" {
  if ! command -v jq >/dev/null 2>&1; then skip "jq required"; fi
  setup_config
  run "$BIN_DIR/worktwin-light-base" get "$TEST_REPO"
  [ "$status" -ne 0 ]
}

@test "remove drops a previously set mapping" {
  if ! command -v jq >/dev/null 2>&1; then skip "jq required"; fi
  setup_config
  mkdir -p "$TEST_BASE/base-target"
  "$BIN_DIR/worktwin-light-base" set "$TEST_REPO" "$TEST_BASE/base-target" >/dev/null
  "$BIN_DIR/worktwin-light-base" remove "$TEST_REPO" >/dev/null
  run "$BIN_DIR/worktwin-light-base" get "$TEST_REPO"
  [ "$status" -ne 0 ]
}

@test "set refuses when base path does not exist" {
  if ! command -v jq >/dev/null 2>&1; then skip "jq required"; fi
  setup_config
  run "$BIN_DIR/worktwin-light-base" set "$TEST_REPO" "$TEST_BASE/missing"
  [ "$status" -ne 0 ]
}
