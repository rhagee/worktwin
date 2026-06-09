---
name: worktwin
description: Set up an isolated git worktree on a dedicated branch and bind this Claude Code session to it. Use when the user wants to spawn a parallel worker that will not interfere with other concurrent sessions on the same repo.
argument-hint: '<from-branch> <new-branch> "<task>"'
arguments: [from_branch, new_branch, task]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(ls *), Bash(test *), Bash(cat *), Bash(jq *), Read, Write, Edit
---

# worktwin

Bind this session to a new parallel worker on branch `$new_branch`, branched from `$from_branch`, with task: `$task`.

The mechanical work runs through `bin/worktwin-init` and `bin/worktwin-claude-md` so the worktree, paths, state file, and rules block are produced the same way every time. Your job is to orchestrate, surface errors, and start working.

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

## 2. Atomic spawn

```bash
"$WORKTWIN_BIN/worktwin-init" "$from_branch" "$new_branch" "$task"
```

The script prints a JSON object on stdout. Capture it and read these fields (use `jq` if available, otherwise parse manually):

- `worktree`
- `state_file`
- `from_ref`
- `warnings` (array)

If the script exits non-zero, show its stderr to the user and stop.

## 3. Pin the rules to the worktree CLAUDE.md

```bash
"$WORKTWIN_BIN/worktwin-claude-md" "<worktree>" "$new_branch" "$from_branch" "$task"
```

The script writes or updates the marked block in the worktree's `CLAUDE.md`. It is idempotent and preserves any other content in the file. This is the only thing that makes the rules survive `/compact` and any new Claude Code session opened in the worktree, so do not skip it.

## 4. Summary

Print to the user:

- Worktree path
- Active branch and source branch
- Task
- State file path
- Any `warnings` from step 2
- Note: any Claude Code session opened in the worktree directory will pick up the rules automatically from CLAUDE.md.

## 5. Start working

Begin the task. Read the relevant files in the worktree. Stay inside the worktree. Make atomic commits as you go.
