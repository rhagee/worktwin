#!/usr/bin/env bats

load test_helper

setup_worktree() {
  WT="$TEST_BASE/wt"
  mkdir -p "$WT"
  export WT
}

@test "creates CLAUDE.md when missing" {
  setup_worktree
  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  [ -f "$WT/CLAUDE.md" ]
  grep -q 'BEGIN worktwin' "$WT/CLAUDE.md"
  grep -q 'END worktwin' "$WT/CLAUDE.md"
}

@test "preserves existing content outside the block" {
  setup_worktree
  printf '# project rules\n\nbe nice.\n' > "$WT/CLAUDE.md"
  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  grep -q 'BEGIN worktwin' "$WT/CLAUDE.md"
  grep -q 'be nice.' "$WT/CLAUDE.md"
}

@test "replaces existing block in place" {
  setup_worktree
  cat > "$WT/CLAUDE.md" <<'EOF'
<!-- BEGIN worktwin -->
old block content
<!-- END worktwin -->

other content
EOF
  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  ! grep -q 'old block content' "$WT/CLAUDE.md"
  grep -q 'feat/x' "$WT/CLAUDE.md"
  grep -q 'other content' "$WT/CLAUDE.md"
}

@test "idempotent: two runs produce identical files" {
  setup_worktree
  "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing" >/dev/null
  cp "$WT/CLAUDE.md" "$WT/CLAUDE.md.first"
  "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing" >/dev/null
  cmp -s "$WT/CLAUDE.md" "$WT/CLAUDE.md.first"
}

@test "fails when worktree directory does not exist" {
  run "$BIN_DIR/worktwin-claude-md" "$TEST_BASE/nope" "feat/x" "main" "do thing"
  [ "$status" -ne 0 ]
}
