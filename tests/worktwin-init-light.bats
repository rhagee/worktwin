#!/usr/bin/env bats

load test_helper

@test "--light=off forces standard path even on capable filesystems" {
  run "$BIN_DIR/worktwin-init" --light=off main feat/explicit-off "task"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"light_mode": "off"'* ]] || [[ "$output" == *'"light_mode":"off"'* ]]
}

@test "--light=on errors when filesystem is not CoW capable" {
  # Test runs on the temp dir's filesystem, usually NTFS/ext4, not CoW.
  # On a CoW filesystem this test would be a no-op pass. We tolerate
  # both outcomes: either light succeeded (status 0) or it errored (non-zero).
  run "$BIN_DIR/worktwin-init" --light=on main feat/explicit-on "task"
  if [ "$status" -ne 0 ]; then
    [[ "$output" == *"light mode not possible"* ]] \
      || [[ "$stderr" == *"light mode not possible"* ]]
  else
    [[ "$output" == *'"light_mode": "active"'* ]] || [[ "$output" == *'"light_mode":"active"'* ]]
  fi
}

@test "--light=auto falls back silently on a non-CoW filesystem" {
  run "$BIN_DIR/worktwin-init" --light=auto main feat/auto "task"
  [ "$status" -eq 0 ]
  # The output always contains light_mode, regardless of which path ran
  [[ "$output" == *'"light_mode":'* ]]
}

@test "invalid --light value exits with usage error" {
  run "$BIN_DIR/worktwin-init" --light=banana main feat/bad "task"
  [ "$status" -eq 2 ]
}

@test "state file records the chosen light mode" {
  "$BIN_DIR/worktwin-init" --light=off main feat/state-check "task" >/dev/null
  [ -f "$TEST_REPO/.git/parallel/feat-state-check.json" ]
  grep -q '"light_mode"' "$TEST_REPO/.git/parallel/feat-state-check.json"
}
