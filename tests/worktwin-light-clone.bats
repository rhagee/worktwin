#!/usr/bin/env bats

load test_helper

@test "fails with missing args" {
  run "$BIN_DIR/worktwin-light-clone"
  [ "$status" -eq 2 ]
}

@test "fails when source does not exist" {
  mkdir -p "$TEST_BASE/dst"
  run "$BIN_DIR/worktwin-light-clone" "$TEST_BASE/no-src" "$TEST_BASE/dst"
  [ "$status" -ne 0 ]
}

@test "fails when destination does not exist" {
  mkdir -p "$TEST_BASE/src"
  run "$BIN_DIR/worktwin-light-clone" "$TEST_BASE/src" "$TEST_BASE/no-dst"
  [ "$status" -ne 0 ]
}

@test "copies top-level entries but skips .git" {
  mkdir -p "$TEST_BASE/src/.git/objects"
  mkdir -p "$TEST_BASE/src/sub"
  echo content > "$TEST_BASE/src/file.txt"
  echo gitfile > "$TEST_BASE/src/.git/config"
  echo subfile > "$TEST_BASE/src/sub/inner.txt"
  mkdir -p "$TEST_BASE/dst"

  run "$BIN_DIR/worktwin-light-clone" "$TEST_BASE/src" "$TEST_BASE/dst"
  [ "$status" -eq 0 ]
  [ -f "$TEST_BASE/dst/file.txt" ]
  [ -f "$TEST_BASE/dst/sub/inner.txt" ]
  [ ! -e "$TEST_BASE/dst/.git" ]
}
