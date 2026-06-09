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

SRC="$(cd "$(dirname "$0")" && pwd)/skills"
if [ ! -d "$SRC" ]; then
  echo "ERROR: skills/ directory not found at $SRC"
  exit 1
fi

mkdir -p "$TARGET"
for skill in worktwin worktwin-ship worktwin-status; do
  rm -rf "$TARGET/$skill"
  cp -r "$SRC/$skill" "$TARGET/"
done

echo "worktwin installed to $TARGET"
echo
echo "Commands available in Claude Code:"
echo "  /worktwin <from-branch> <new-branch> \"<task>\""
echo "  /worktwin-ship [branch1 branch2 ...]"
echo "  /worktwin-status"
