---
name: worktwin-finalize
description: Wrap up worktwin workers locally without pushing or creating pull requests. Shows what was done on each branch and drafts a suggested PR title and body the user can copy when they push themselves. Use when gh is not available, when working on enterprise repos that forbid auto-PRs, or when you want to review locally first.
argument-hint: "[branch1 branch2 ...]   leave empty to finalize all active workers"
arguments: [branches]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(ls *), Bash(test *), Bash(jq *), Bash(grep *), Read
---

# worktwin-finalize

Report on one or more workers and draft what their pull request would look like, without touching the remote. No `git push`, no `gh` calls.

## 1. Locate the bin directory

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
```

## 2. Discover workers

```bash
"$WORKTWIN_BIN/worktwin-list" "$@"
```

If the user passed branch arguments, the script already filters to those. If the output is empty, print `no active worktwin workers to finalize` and stop.

## 3. Per-worker report

For each worker, print:

- Branch and base branch
- Worktree path
- Assigned task
- Commit list: `git log <from_branch>..<branch>` (with bodies)
- File changes: `git diff --name-status <from_branch>..<branch>`
- Working tree status: `git -C "<worktree>" status --porcelain`. Warn if uncommitted changes are present, because they would be lost on the suggested push.

## 4. Draft the PR content

For each worker, draft a real PR title and body the way a developer would. Read the full commit messages, the diff, the task, and the repo's `CONTRIBUTING.md` plus the last 20 base-branch commit messages (`git log <from_branch> -20 --format='%s'`) to match the project's conventions.

Then print the draft in a clearly delimited block so it is easy to copy:

```
--- suggested PR for <branch> ---
title: <title>

<body>
--- end ---
```

End the body with a single trailing line: `Opened by worktwin.`

## 5. Manual commands

For each finalized worker, print the exact commands the user needs to ship it themselves, with placeholders already filled in:

```
git push <remote> <branch>
gh pr create --base <from_branch> --head <branch> --title "<title>" --body "<body>" --draft
```

Pick the remote with `git remote | grep -x origin || git remote | head -n1`. If no remote is configured, print only the `git push` placeholder and tell the user to add a remote first.

## 6. No state changes

Finalize must not remove worktrees, must not delete state files, must not push, must not call `gh`.

## 7. Final table

Recap every finalized worker:

```
| Branch | Base | Commits | Files | Uncommitted | Ready |
```

`Ready` is `yes` if commits ahead > 0 and uncommitted == 0, `no` otherwise.
