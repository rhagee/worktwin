---
name: worktwin-status
description: List every active worktwin worker on the current repository with their branch, worktree path, task, and progress. Use when the user wants a quick overview without entering a shipping flow.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(ls *), Bash(test *), Bash(jq *), Read
---

# worktwin-status

Show every active worker on the current repository. Read-only, no side effects.

## 1. Locate the bin directory

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
if [ -z "$WORKTWIN_BIN" ]; then
  echo "ERROR: worktwin bin/ not found. Did install.sh / install.ps1 complete?" >&2
  exit 1
fi
```

## 2. List workers

```bash
"$WORKTWIN_BIN/worktwin-list"
```

The script emits one JSON line per worker (NDJSON) with: `branch`, `from_branch`, `worktree`, `task`, `started_at`, `worktree_exists`, `commits_ahead`, `files_changed`, `uncommitted`. With no parallel directory it exits silently with no output.

If the output is empty, print `no active worktwin workers` and stop.

## 3. Render

Print one compact table:

```
| Branch | Base | Light | Worktree | Commits | Files | Uncommitted | Task |
```

The Light column shows `yes` when `light_mode` is `active`, blank otherwise.

For workers where `worktree_exists` is `false`, replace the worktree column with `stale (worktree gone)` and the metric columns with `-`. Truncate the task column to a sensible width.

Append two hint lines below the table:

```
run /worktwin-ship <branch> to ship one, /worktwin-ship-all for the batch, or /worktwin-finalize for a local-only summary
run /worktwin-clear <branch> to drop a stale entry (worktree gone)
```

If no workers are stale, you can skip the second hint.
