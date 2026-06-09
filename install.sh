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
for skill in worktwin worktwin-ship worktwin-ship-all worktwin-finalize worktwin-status worktwin-help; do
  rm -rf "$TARGET/$skill"
  cp -r "$SRC/$skill" "$TARGET/"
done

BIN_SRC="$(cd "$(dirname "$0")" && pwd)/bin"
if [ -d "$BIN_SRC" ]; then
  BIN_DST="$TARGET/worktwin/bin"
  mkdir -p "$BIN_DST"
  cp "$BIN_SRC"/* "$BIN_DST/"
  chmod +x "$BIN_DST"/worktwin-init "$BIN_DST"/worktwin-claude-md "$BIN_DST"/worktwin-list 2>/dev/null || true
fi

echo "worktwin installed to $TARGET"
echo
echo "Run /worktwin-help inside Claude Code to see every command."
echo "Standalone CLI tools at $TARGET/worktwin/bin"
