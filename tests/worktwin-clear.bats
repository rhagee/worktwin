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

@test "removes worktree and state when worker is clean" {
  "$BIN_DIR/worktwin-init" main feat/clean "task" >/dev/null
  run "$BIN_DIR/worktwin-clear" feat/clean
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_BASE/myrepo--feat-clean" ]
  [ ! -f "$TEST_REPO/.git/parallel/feat-clean.json" ]
}

@test "refuses to clear when worktree has uncommitted changes" {
  "$BIN_DIR/worktwin-init" main feat/dirty "task" >/dev/null
  echo "scratch" > "$TEST_BASE/myrepo--feat-dirty/dirty.txt"
  run "$BIN_DIR/worktwin-clear" feat/dirty
  [ "$status" -ne 0 ]
  [[ "$output" == *"uncommitted"* ]] || [[ "$stderr" == *"uncommitted"* ]]
  [ -f "$TEST_REPO/.git/parallel/feat-dirty.json" ]
}

@test "--force discards uncommitted changes and clears" {
  "$BIN_DIR/worktwin-init" main feat/nuke "task" >/dev/null
  echo "scratch" > "$TEST_BASE/myrepo--feat-nuke/dirty.txt"
  run "$BIN_DIR/worktwin-clear" --force feat/nuke
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_BASE/myrepo--feat-nuke" ]
  [ ! -f "$TEST_REPO/.git/parallel/feat-nuke.json" ]
}

@test "removes the state file when the worktree is already gone" {
  "$BIN_DIR/worktwin-init" main feat/gone "task" >/dev/null
  rm -rf "$TEST_BASE/myrepo--feat-gone"
  run "$BIN_DIR/worktwin-clear" feat/gone
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_REPO/.git/parallel/feat-gone.json" ]
}
