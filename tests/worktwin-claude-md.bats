#!/usr/bin/env bats

load test_helper

setup_worktree() {
  WT="$TEST_BASE/wt"
  mkdir -p "$WT"
  export WT
}

# Create a real linked git worktree so the tracked / untracked / exclude
# code paths can be exercised end-to-end.
setup_real_worktree() {
  WT="$TEST_BASE/wt"
  git -C "$TEST_REPO" worktree add -q -b feat/x "$WT" main
  export WT
}

@test "creates WORKTWIN.md with task and rules" {
  setup_worktree
  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  [ -f "$WT/WORKTWIN.md" ]
  grep -q '# worktwin parallel worker context' "$WT/WORKTWIN.md"
  grep -q '## Task' "$WT/WORKTWIN.md"
  grep -q 'do thing' "$WT/WORKTWIN.md"
  grep -q 'feat/x' "$WT/WORKTWIN.md"
}

@test "creates CLAUDE.md with only the tail block when missing" {
  setup_worktree
  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  [ -f "$WT/CLAUDE.md" ]
  grep -q 'BEGIN worktwin' "$WT/CLAUDE.md"
  grep -q 'END worktwin' "$WT/CLAUDE.md"
  grep -q '@WORKTWIN.md' "$WT/CLAUDE.md"
}

@test "appends tail block to the bottom of existing CLAUDE.md" {
  setup_worktree
  printf '# project rules\n\nbe nice.\n' > "$WT/CLAUDE.md"
  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  grep -q '# project rules' "$WT/CLAUDE.md"
  grep -q 'be nice.' "$WT/CLAUDE.md"
  grep -q '@WORKTWIN.md' "$WT/CLAUDE.md"
  # original content must precede the worktwin block (tail placement)
  project_line=$(grep -n '# project rules' "$WT/CLAUDE.md" | cut -d: -f1)
  begin_line=$(grep -n 'BEGIN worktwin'   "$WT/CLAUDE.md" | cut -d: -f1)
  [ "$project_line" -lt "$begin_line" ]
}

@test "replaces existing worktwin block wherever it sits" {
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
  grep -q '@WORKTWIN.md' "$WT/CLAUDE.md"
  grep -q 'other content' "$WT/CLAUDE.md"
  # block ends up at the bottom now
  other_line=$(grep -n 'other content'  "$WT/CLAUDE.md" | cut -d: -f1)
  begin_line=$(grep -n 'BEGIN worktwin' "$WT/CLAUDE.md" | cut -d: -f1)
  [ "$other_line" -lt "$begin_line" ]
}

@test "idempotent: two runs produce identical files" {
  setup_worktree
  "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing" >/dev/null
  cp "$WT/CLAUDE.md"   "$WT/CLAUDE.md.first"
  cp "$WT/WORKTWIN.md" "$WT/WORKTWIN.md.first"
  "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing" >/dev/null
  cmp -s "$WT/CLAUDE.md"   "$WT/CLAUDE.md.first"
  cmp -s "$WT/WORKTWIN.md" "$WT/WORKTWIN.md.first"
}

@test "fails when worktree directory does not exist" {
  run "$BIN_DIR/worktwin-claude-md" "$TEST_BASE/nope" "feat/x" "main" "do thing"
  [ "$status" -ne 0 ]
}

@test "marks tracked CLAUDE.md skip-worktree in a real worktree" {
  # Add a tracked CLAUDE.md on main so the worktree inherits it as tracked.
  printf '# company rules\n' > "$TEST_REPO/CLAUDE.md"
  git -C "$TEST_REPO" add CLAUDE.md
  git -C "$TEST_REPO" commit -q -m "add company CLAUDE.md"
  setup_real_worktree

  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  # company content preserved
  grep -q '# company rules' "$WT/CLAUDE.md"
  # tail block appended
  grep -q '@WORKTWIN.md' "$WT/CLAUDE.md"
  # skip-worktree bit set on the tracked file
  git -C "$WT" ls-files -v CLAUDE.md | grep -q '^S '
  # working tree dirty but git sees no changes thanks to skip-worktree
  status_out=$(git -C "$WT" status --porcelain)
  [[ "$status_out" != *"CLAUDE.md"* ]]
}

@test "adds untracked WORKTWIN.md and CLAUDE.md to per-worktree exclude" {
  # No CLAUDE.md on main this time; both files end up untracked.
  setup_real_worktree

  run "$BIN_DIR/worktwin-claude-md" "$WT" "feat/x" "main" "do thing"
  [ "$status" -eq 0 ]
  exclude_path=$(git -C "$WT" rev-parse --git-path info/exclude)
  case "$exclude_path" in
    /*|[A-Za-z]:[\\/]*) ;;
    *) exclude_path="$WT/$exclude_path" ;;
  esac
  [ -f "$exclude_path" ]
  grep -qxF '/WORKTWIN.md' "$exclude_path"
  grep -qxF '/CLAUDE.md'   "$exclude_path"
  # neither file shows up in git status
  status_out=$(git -C "$WT" status --porcelain)
  [[ "$status_out" != *"CLAUDE.md"* ]]
  [[ "$status_out" != *"WORKTWIN.md"* ]]
}
