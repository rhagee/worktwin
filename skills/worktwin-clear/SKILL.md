---
name: worktwin-clear
description: Mark a worktwin worker as complete and remove it from the active list. Removes the worktree directory (if present) and the parallel/ state file. Use after a manual ship via /worktwin-finalize, or to drop a stale entry whose worktree was already removed. Accepts --force to discard uncommitted changes.
argument-hint: '[--force] <branch>'
arguments: [branch]
disable-model-invocation: true
allowed-tools: Bash(bash *), Bash(test *), Bash(git *)
---

# worktwin-clear

Mark a worker as complete and drop it from `/worktwin-status`. Common case after a manual ship via `/worktwin-finalize`: the user pushed and opened the PR themselves, now they want worktwin to forget the local state.

The mechanical work runs in `bin/worktwin-clear`. Safe by default: the script refuses if the worktree has uncommitted changes. `--force` overrides.

## 1. Parse arguments

Walk `$@` and capture:

- A boolean `FORCE` flag. Set true if `--force` appears.
- The branch name (the first non-flag argument).

If no branch was passed, stop with:

```
worktwin-clear requires a branch. Use /worktwin-clear [--force] <branch>.
```

## 2. Locate the bin directory

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
```

## 3. Run the clear

```bash
if [ $FORCE -eq 1 ]; then
  "$WORKTWIN_BIN/worktwin-clear" --force "$branch"
else
  "$WORKTWIN_BIN/worktwin-clear" "$branch"
fi
```

Surface the script's stdout and stderr to the user.

- Exit code 0: the entry is gone. Tell the user what was removed (worktree path, state file).
- Exit code 1 with "uncommitted change(s)": the worker still has work in progress. Tell the user the options: commit, stash, or re-invoke as `/worktwin-clear --force <branch>` to discard. Do not auto-retry with --force; the safety prompt is the whole point.
- Exit code 1 with "no state file found": the branch is not a known worktwin worker.

## 4. Recap

If the clear succeeded, suggest running `/worktwin-status` again to confirm the entry is gone.
