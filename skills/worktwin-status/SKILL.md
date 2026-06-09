---
name: worktwin-status
description: List every active worktwin worker on the current repository with their branch, worktree path, task, and progress. Use when the user wants a quick overview without entering the ship flow.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(cat *), Bash(ls *), Bash(jq *), Read
---

# worktwin-status

Show a quick report of every active parallel worker for the current repository. Read-only, no side effects.

## 1. Locate the state directory

```bash
PARALLEL_DIR="$(git rev-parse --git-common-dir)/parallel"
```

If the directory does not exist or is empty, print `no active worktwin workers` and stop.

## 2. Read each state file

For every `*.json` file in `$PARALLEL_DIR`, extract `branch`, `from_branch`, `worktree`, `task`, `started_at`.

If `jq` is available, parse with `jq -r '...'`. Otherwise read the file and parse the fields directly.

## 3. Per-worker progress

For each worker, with the worktree still present on disk:

- Commits ahead: `git -C "<worktree>" log "<from_branch>..<branch>" --oneline | wc -l`
- Files changed: `git -C "<worktree>" diff --name-only "<from_branch>..<branch>" | wc -l`
- Uncommitted changes: `git -C "<worktree>" status --porcelain | wc -l`

If the worktree path is missing on disk, flag the worker as `stale (worktree gone)`.

## 4. Output

Print one compact table:

```
| Branch | Base | Worktree | Commits | Files | Uncommitted | Task |
```

Truncate the task column to a sensible width. Append a single hint line below: `run /worktwin-ship <branch> to ship one, /worktwin-ship-all for the batch, or /worktwin-finalize for a local-only summary`.
