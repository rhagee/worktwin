---
name: worktwin-clear
description: Mark one or every worktwin worker as complete and remove from the active list. Removes the worktree directory (if present) and the parallel/ state file. Use after a manual ship via /worktwin-finalize, or to drop stale entries. Accepts --all for batch and --force to discard uncommitted changes.
argument-hint: '[--all] [--force] [<branch>]'
arguments: [branch]
disable-model-invocation: true
allowed-tools: Bash(bash *), Bash(test *), Bash(git *)
---

# worktwin-clear

Mark a worker (or every worker) as complete and drop it from `/worktwin-status`. Common cases:

- After a manual ship via `/worktwin-finalize`: the user pushed and opened the PR themselves, now they want worktwin to forget the local state.
- End of a parallel session where every worker has shipped manually and the user wants to wipe the slate clean.

The mechanical work runs in `bin/worktwin-clear`. Safe by default: dirty workers are refused (single mode) or skipped (--all mode). `--force` overrides.

## 1. Parse arguments

Walk `$@` and capture:

- A boolean `FORCE` flag. Set true if `--force` appears.
- A boolean `ALL` flag. Set true if `--all` appears.
- The branch name (the first non-flag argument, if any).

Validation:

- If neither `ALL` nor a branch was passed, stop with:
  ```
  worktwin-clear requires a branch or --all. Use /worktwin-clear [--force] <branch> or /worktwin-clear --all [--force].
  ```
- If `ALL` was set together with a branch, stop with:
  ```
  do not combine --all with a branch name.
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

Build the argument list from the flags and run the script:

```bash
ARGS=()
[ $ALL -eq 1 ] && ARGS+=("--all")
[ $FORCE -eq 1 ] && ARGS+=("--force")
[ -n "$branch" ] && ARGS+=("$branch")
"$WORKTWIN_BIN/worktwin-clear" "${ARGS[@]}"
```

Surface the script's stdout and stderr to the user.

Single mode (`<branch>`):

- Exit code 0: the entry is gone. Tell the user what was removed.
- Exit code 1 with "uncommitted change(s)": the worker still has work in progress. Tell the user the options: commit, stash, or re-invoke as `/worktwin-clear --force <branch>` to discard. Do not auto-retry with `--force`; the safety prompt is the whole point.
- Exit code 1 with "no state file found": the branch is not a known worktwin worker.

Batch mode (`--all`):

- Exit code 0 with a `summary: N cleared` line at the end: every worker was clean and got removed.
- Exit code 0 with a `summary: X cleared, Y skipped` line: some workers had uncommitted state. The output lists which ones were skipped. Tell the user they can re-run as `/worktwin-clear --all --force` to discard everything, or clean up the skipped workers manually first.

## 4. Recap

If the clear succeeded, suggest running `/worktwin-status` again to confirm the entry is gone.
