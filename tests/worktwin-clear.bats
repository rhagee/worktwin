#!/usr/bin/env bats

load test_helper

@test "fails with missing argument" {
  run "$BIN_DIR/worktwin-clear"
  [ "$status" -eq 2 ]
}

@test "fails when no state file matches the branch" {
  run "$BIN_DIR/worktwin-clear" no-such-branch
  [ "$status" -ne 0 ]
}

@test "refuses to clear when the worktree still exists" {
  "$BIN_DIR/worktwin-init" main feat/keep "task" >/dev/null
  run "$BIN_DIR/worktwin-clear" feat/keep
  [ "$status" -ne 0 ]
  [[ "$output" == *"worktree still exists"* ]] \
    || [[ "$stderr" == *"worktree still exists"* ]]
  [ -f "$TEST_REPO/.git/parallel/feat-keep.json" ]
}

@test "removes the state file when the worktree is gone" {
  "$BIN_DIR/worktwin-init" main feat/gone "task" >/dev/null
  rm -rf "$TEST_BASE/myrepo--feat-gone"
  run "$BIN_DIR/worktwin-clear" feat/gone
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_REPO/.git/parallel/feat-gone.json" ]
}
