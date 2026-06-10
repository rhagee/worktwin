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
for skill in worktwin worktwin-ship worktwin-ship-all worktwin-finalize worktwin-merge-solver worktwin-status worktwin-clear worktwin-light-doctor worktwin-light-setup-windows worktwin-light-teardown-windows worktwin-help worktwin-update; do
  rm -rf "$TARGET/$skill"
  cp -r "$SRC/$skill" "$TARGET/"
done

SOURCE_ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN_SRC="$SOURCE_ROOT/bin"
if [ -d "$BIN_SRC" ]; then
  BIN_DST="$TARGET/worktwin/bin"
  mkdir -p "$BIN_DST"
  cp "$BIN_SRC"/* "$BIN_DST/"
  chmod +x "$BIN_DST"/worktwin-init "$BIN_DST"/worktwin-claude-md "$BIN_DST"/worktwin-list "$BIN_DST"/worktwin-clear "$BIN_DST"/worktwin-light-check "$BIN_DST"/worktwin-help "$BIN_DST"/worktwin-update "$BIN_DST"/worktwin-merge-solver 2>/dev/null || true
fi

# Record where this clone lives so worktwin-update can find it later
printf '%s\n' "$SOURCE_ROOT" > "$TARGET/worktwin/.source"

echo "worktwin installed to $TARGET"
echo
echo "Run /worktwin-help inside Claude Code to see every command."
echo "Standalone CLI tools at $TARGET/worktwin/bin"

# Soft dependency check: jq is required by /worktwin-merge-solver in the
# bash flavour. The rest of worktwin works without it. We never install
# packages automatically; we just point the user at the right command
# for their platform.
if ! command -v jq >/dev/null 2>&1; then
  os=$(uname -s 2>/dev/null || echo unknown)
  echo
  echo "note: 'jq' was not found on PATH."
  echo "      it is required by /worktwin-merge-solver (bash flavour)."
  echo "      everything else worktwin installs works without it."
  case "$os" in
    Darwin)
      echo "      install on macOS: brew install jq"
      ;;
    Linux)
      if   command -v apt-get >/dev/null 2>&1; then echo "      install: sudo apt-get install jq"
      elif command -v dnf     >/dev/null 2>&1; then echo "      install: sudo dnf install jq"
      elif command -v pacman  >/dev/null 2>&1; then echo "      install: sudo pacman -S jq"
      elif command -v apk     >/dev/null 2>&1; then echo "      install: sudo apk add jq"
      else                                          echo "      use your distro package manager (search for 'jq')"
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*)
      if   command -v scoop  >/dev/null 2>&1; then echo "      install: scoop install jq"
      elif command -v winget >/dev/null 2>&1; then echo "      install: winget install jqlang.jq"
      elif command -v choco  >/dev/null 2>&1; then echo "      install: choco install jq"
      else                                         echo "      install with scoop / winget / choco, e.g.: scoop install jq"
      fi
      ;;
    *)
      echo "      see https://jqlang.github.io/jq/download/"
      ;;
  esac
fi
