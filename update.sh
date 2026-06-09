#!/usr/bin/env bash
# update.sh - git pull the worktwin repo, then re-run install.sh.
# Run from inside the cloned worktwin repo.
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

echo "Updating worktwin from $REPO_ROOT"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "ERROR: $REPO_ROOT is not a git repository. Run update.sh from the cloned worktwin repo." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "WARN: $REPO_ROOT has uncommitted changes. Skipping git pull, re-running install only."
  SKIP_PULL=1
fi

if [ -z "$SKIP_PULL" ]; then
  echo "git pull..."
  if ! git pull --ff-only; then
    echo "ERROR: git pull failed. Resolve the conflict manually, then re-run update.sh." >&2
    exit 1
  fi
fi

"$REPO_ROOT/install.sh" "$@"
echo
echo "worktwin updated. Restart Claude Code to pick up the new skills."
