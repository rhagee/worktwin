#!/usr/bin/env bats

load test_helper

@test "fails outside a git repo" {
  cd "$TEST_BASE"
  run "$BIN_DIR/worktwin-init" main feat/x "do thing"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not inside a git repository"* ]] || [[ "$stderr" == *"not inside a git repository"* ]]
}

@test "fails with missing arguments" {
  run "$BIN_DIR/worktwin-init" main
  [ "$status" -eq 2 ]
}

@test "creates a worktree from an existing source branch" {
  run "$BIN_DIR/worktwin-init" main feat/x "build x"
  [ "$status" -eq 0 ]
  [ -d "$TEST_BASE/myrepo--feat-x" ]
}

@test "writes a state file at git-common-dir/parallel" {
  run "$BIN_DIR/worktwin-init" main feat/y "task y"
  [ "$status" -eq 0 ]
  [ -f "$TEST_REPO/.git/parallel/feat-y.json" ]
}

@test "sanitises slug, replacing non-alnum characters" {
  run "$BIN_DIR/worktwin-init" main "feat/has spaces" "task"
  [ "$status" -eq 0 ]
  [ -d "$TEST_BASE/myrepo--feat-has-spaces" ]
}

@test "output JSON contains the expected fields" {
  run "$BIN_DIR/worktwin-init" main feat/z "task z"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"worktree"'* ]]
  [[ "$output" == *'"branch"'* ]]
  [[ "$output" == *'"from_branch"'* ]]
  [[ "$output" == *'"state_file"'* ]]
  [[ "$output" == *'"warnings"'* ]]
}

@test "reusing an existing worktree does not fail" {
  "$BIN_DIR/worktwin-init" main feat/w "task w" >/dev/null
  run "$BIN_DIR/worktwin-init" main feat/w "task w"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reusing"* ]] || true
}

@test "fails when source branch does not exist locally or on origin" {
  run "$BIN_DIR/worktwin-init" nosuch-branch feat/dead "task"
  [ "$status" -ne 0 ]
}
