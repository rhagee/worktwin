#!/usr/bin/env bats

load test_helper

@test "exits silently when parallel directory is missing" {
  run "$BIN_DIR/worktwin-list"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "emits one line per worker" {
  "$BIN_DIR/worktwin-init" main feat/a "task a" >/dev/null
  "$BIN_DIR/worktwin-init" main feat/b "task b" >/dev/null
  run "$BIN_DIR/worktwin-list"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "filters by branch arguments" {
  "$BIN_DIR/worktwin-init" main feat/keep "task keep" >/dev/null
  "$BIN_DIR/worktwin-init" main feat/skip "task skip" >/dev/null
  run "$BIN_DIR/worktwin-list" feat/keep
  [ "$status" -eq 0 ]
  [[ "$output" == *"feat/keep"* ]]
  [[ "$output" != *"feat/skip"* ]]
}

@test "marks workers with missing worktrees as not existing" {
  "$BIN_DIR/worktwin-init" main feat/gone "task" >/dev/null
  rm -rf "$TEST_BASE/myrepo--feat-gone"
  run "$BIN_DIR/worktwin-list"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"worktree_exists":false'* ]] \
    || [[ "$output" == *'"worktree_exists": false'* ]]
}

@test "each line is valid JSON" {
  "$BIN_DIR/worktwin-init" main feat/json "task json" >/dev/null
  run "$BIN_DIR/worktwin-list"
  [ "$status" -eq 0 ]
  # Crude JSON shape check that does not require jq
  while IFS= read -r line; do
    [[ "$line" == "{"* ]]
    [[ "$line" == *"}" ]]
  done <<< "$output"
}
