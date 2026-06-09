---
name: worktwin-finalize
description: Wrap up worktwin workers locally without pushing or creating pull requests. Shows what was done on each branch and drafts a suggested PR title and body the user can copy when they push themselves. Use when gh is not available, when working on enterprise repos that forbid auto-PRs, or when you want to review locally first.
argument-hint: "[branch1 branch2 ...]   leave empty to finalize all active workers"
arguments: [branches]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(cat *), Bash(ls *), Bash(find *), Bash(echo *), Bash(jq *), Bash(grep *), Read
---

# worktwin-finalize

Report on one or more workers and draft what their pull request would look like, without touching the remote. Read-only with respect to git remotes: no push, no `gh` calls, no PR creation.

## 1. Discover the target workers

```bash
PARALLEL_DIR="$(git rev-parse --git-common-dir)/parallel"
```

If the user passed branch arguments, restrict the set to those. Otherwise read every `*.json` in `$PARALLEL_DIR`. Fall back to `git worktree list --porcelain` if the parallel directory is empty.

If nothing is found, print `no active worktwin workers to finalize` and stop.

## 2. Per-worker report

For each worker, gather and print:

- Branch and base branch
- Worktree path
- Assigned task (from the state file)
- Commit list: `git log <from_branch>..<branch>` (full messages, not just `--oneline`)
- File changes: `git diff --name-status <from_branch>..<branch>`
- Working tree status: `git -C "<worktree>" status --porcelain`. Warn if uncommitted changes are present, because they would be lost on the suggested push.

## 3. Draft the PR content

For each worker, draft a real pull request title and body, the way a developer would. Read:

- The full commit messages, for the substance.
- The diff, for what actually changed.
- The repository's `CONTRIBUTING.md` if present, and the last 20 commit messages on the base branch (`git log <from_branch> -20 --format='%s'`), to match the project's tone and conventions.

Then write:

- A title that matches the conventions you observed.
- A body that explains what changed and why, with a bullet list of notable commits or files, plus any caveats.

Keep it short. Two or three paragraphs plus bullets is the right size for most PRs.

Print the draft in a clearly delimited block so the user can copy it without picking it apart:

```
--- suggested PR for <branch> ---
title: <title>

<body>
--- end ---
```

Append a single trailing line at the bottom of the body: `Opened by worktwin.`

## 4. Hand the user the manual commands

For each finalized worker, print the exact commands they need to ship it themselves, with placeholders already filled in:

```
git push <remote> <branch>
gh pr create --base <from_branch> --head <branch> --title "<title>" --body "<body>" --draft
```

Pick the remote with `git remote | grep -x origin || git remote | head -n1`. If no remote is configured, print only the `git push` placeholder and tell the user to add a remote first.

## 5. No cleanup, no state changes

Finalize must not remove worktrees, must not delete state files, must not push, must not call `gh`. The whole point of this command is that the user is in control of the network side. Leave everything as it is.

## 6. Final table

End with a recap:

```
| Branch | Base | Commits | Files | Uncommitted | Ready |
```

`Ready` is `yes` for workers with commits ahead and a clean tree, `no` for workers with uncommitted changes or zero commits.
