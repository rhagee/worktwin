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

for skill in worktwin worktwin-ship worktwin-ship-all worktwin-finalize worktwin-status worktwin-clear worktwin-light-doctor worktwin-light-setup-windows worktwin-help worktwin-update; do
  rm -rf "$TARGET/$skill"
done
# bin/ and .source live inside the worktwin skill dir and are removed with it

echo "worktwin removed from $TARGET"
