#!/usr/bin/env bash
set -e

MODE="${1:-global}"

case "$MODE" in
  global)
    TARGET="$HOME/.claude/skills"
    ;;
  local)
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ -z "$REPO_ROOT" ]; then
      echo "ERROR: 'local' mode requires running inside a git repo"
      exit 1
    fi
    TARGET="$REPO_ROOT/.claude/skills"
    ;;
  *)
    TARGET="$MODE/.claude/skills"
    ;;
esac

for skill in worktwin worktwin-ship worktwin-ship-all worktwin-finalize worktwin-status worktwin-help; do
  rm -rf "$TARGET/$skill"
done
# bin/ is removed as part of the worktwin skill directory above

echo "worktwin removed from $TARGET"
