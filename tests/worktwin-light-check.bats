#!/usr/bin/env bats

load test_helper

@test "light-check outputs all required JSON fields" {
  run "$BIN_DIR/worktwin-light-check" "$TEST_REPO"
  [ "$status" -eq 0 ]
  for field in '"os":' '"filesystem":' '"cow_capable":' '"path":' '"reason":' '"recommendation":'; do
    [[ "$output" == *"$field"* ]] || { echo "missing field: $field" >&2; false; }
  done
}

@test "light-check is silent about errors when path does not exist" {
  run "$BIN_DIR/worktwin-light-check" "$TEST_BASE/no-such-path"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"cow_capable":'* ]]
}

@test "light-check default path is current directory" {
  cd "$TEST_REPO"
  run "$BIN_DIR/worktwin-light-check"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"path":'* ]]
}

@test "light-check recommendation is one of the documented values" {
  run "$BIN_DIR/worktwin-light-check" "$TEST_REPO"
  [ "$status" -eq 0 ]
  found=0
  for rec in '"ready"' '"switch-path"' '"create-volume"' '"remount"' '"filesystem-not-supported"' '"run-powershell-mirror"'; do
    if [[ "$output" == *"\"recommendation\":$rec"* ]] || [[ "$output" == *"\"recommendation\": $rec"* ]]; then
      found=1
      break
    fi
  done
  [ $found -eq 1 ]
}
