---
name: worktwin
description: Set up an isolated git worktree on a dedicated branch and bind this Claude Code session to it. Use when the user wants to spawn a parallel worker that will not interfere with other concurrent sessions on the same repo.
argument-hint: <from-branch> <new-branch> "<task>"
arguments: [from_branch, new_branch, task]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(mkdir *), Bash(ls *), Bash(pwd *), Bash(cat *), Bash(dirname *), Bash(basename *), Bash(date *), Bash(jq *), Bash(sed *), Read, Write, Edit
---

# worktwin

Bind this session to a new parallel worker on branch `$new_branch`, branched from `$from_branch`, with task: `$task`.

Follow the steps in order. Stop and report to the user on any error.

## 1. Verify git repo

Run `git rev-parse --show-toplevel`. If it fails, abort with: "worktwin must be run from inside a git repository."

## 2. Compute paths

Use the shared git directory so state is discoverable from every worktree of the repo (not just the main checkout).

```bash
GIT_COMMON_DIR=$(git rev-parse --git-common-dir)
MAIN_REPO=$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)
REPO_NAME=$(basename "$MAIN_REPO")
BRANCH_SLUG=$(echo "$new_branch" | sed 's|[^a-zA-Z0-9._-]|-|g')
WORKTREE_PATH="$(dirname "$MAIN_REPO")/${REPO_NAME}--${BRANCH_SLUG}"
```

If the current working directory is not `$MAIN_REPO`, warn that worktwin was invoked from inside another worktree and is using the main repo as the base.

## 3. Resolve the source branch

```bash
if git rev-parse --verify "$from_branch" >/dev/null 2>&1; then
  FROM_REF="$from_branch"
elif git fetch origin "$from_branch" >/dev/null 2>&1 \
     && git rev-parse --verify "origin/$from_branch" >/dev/null 2>&1; then
  FROM_REF="origin/$from_branch"
else
  echo "ERROR: source branch '$from_branch' not found locally or on origin"; exit 1
fi
```

## 4. Create the worktree

If branch `$new_branch` already exists locally, attach it:
`git worktree add "$WORKTREE_PATH" "$new_branch"`

Otherwise create it from the resolved source:
`git worktree add -b "$new_branch" "$WORKTREE_PATH" "$FROM_REF"`

If the path is already a registered worktree, skip the add and continue without error.

## 5. Write the worker state file

Path: `$GIT_COMMON_DIR/parallel/$BRANCH_SLUG.json`.

`mkdir -p` the parallel directory. Then write the JSON with the Write tool (do not use a bash heredoc; quotes or newlines in `$task` would corrupt the file). Fields:

```json
{
  "branch": "<new_branch>",
  "from_branch": "<from_branch>",
  "worktree": "<WORKTREE_PATH>",
  "task": "<task>",
  "started_at": "<ISO 8601 timestamp>",
  "status": "active"
}
```

## 6. Pin the rules to the worktree CLAUDE.md

Read `$WORKTREE_PATH/CLAUDE.md` if it exists. Write or update it so the worktwin rules block sits at the top, delimited by markers. The marked block is idempotent: if a previous `<!-- BEGIN worktwin -->` to `<!-- END worktwin -->` block exists, replace it. Do not touch content outside the markers.

This is the only mechanism that makes the rules survive `/compact` and any new Claude Code session opened in the worktree, so do not skip this step.

Block content to write:

```
<!-- BEGIN worktwin -->
# worktwin parallel worker rules

This session is bound to branch `<new_branch>` in worktree `<WORKTREE_PATH>`.
These rules apply for the whole session, every follow-up message, and any new
Claude Code session opened in this directory.

DO
- Work only inside `<WORKTREE_PATH>`.
- Stay on branch `<new_branch>` for the entire session.
- Make atomic commits with messages like `feat(scope): description`.
- After each meaningful unit of work, commit.
- If the user asks you to continue or iterate, keep working on the same branch.

DO NOT
- Run `git checkout` or `git switch` to a different branch.
- Modify files outside `<WORKTREE_PATH>`.
- Run `git merge` or `git rebase` unless the user explicitly asks.
- Delete the `parallel/` state files.
- Push to any branch other than `<new_branch>`.

Task: <task>
<!-- END worktwin -->
```

Substitute the angle-bracketed placeholders with the actual values before writing.

## 7. Summary

Print to the user:
- Worktree path
- Active branch and source branch
- Assigned task
- State file path
- Note: any Claude Code session opened in the worktree directory will pick up the rules automatically from CLAUDE.md.

Then start working on the task: read the relevant files in the worktree and proceed step by step. Stay inside the worktree. Commit as you go.
