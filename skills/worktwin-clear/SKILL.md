---
name: worktwin-clear
description: Remove the state file for a stale worktwin worker (worktree gone but state lingers). Refuses to touch live workers. Use when /worktwin-status shows an entry as stale and you want it off the list.
argument-hint: '<branch>'
arguments: [branch]
disable-model-invocation: true
allowed-tools: Bash(bash *), Bash(test *), Bash(git *)
---

# worktwin-clear

Drop the state entry for a stale worker. The mechanical work runs in `bin/worktwin-clear`, which only acts when the worktree is genuinely missing from disk.

## 1. Require a branch argument

If `$branch` is empty, stop with:

```
worktwin-clear requires a branch. Use /worktwin-clear <branch>.
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
"$WORKTWIN_BIN/worktwin-clear" "$branch"
```

Surface the script's stdout and stderr to the user.

- Exit code 0: state removed, tell the user the entry is gone.
- Exit code 1 with "worktree still exists": explain that the user should ship, finalize, or `git worktree remove` first. Do not retry, do not force.
- Exit code 1 with "no state file found": tell the user the branch is not a known worktwin worker.

## 4. Recap

If the clear succeeded, suggest running `/worktwin-status` again to confirm the entry is gone.
