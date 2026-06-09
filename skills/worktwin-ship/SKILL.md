---
name: worktwin-ship
description: Push and open or update GitHub pull requests for one or more specific worktwin workers. Use when a subset of parallel workers are done and you want to ship them without touching the others. Requires at least one branch argument.
argument-hint: '<branch> [<branch> ...]'
arguments: [branches]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(test *), Bash(jq *), Bash(grep *), Read
---

# worktwin-ship

Ship the specific workers passed as arguments. Push their branches, open or update draft pull requests, and report.

## 1. Require explicit branches

If no argument was passed, stop with:

```
worktwin-ship requires at least one branch. Use /worktwin-ship <branch> or /worktwin-ship-all.
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

## 3. Resolve workers

```bash
"$WORKTWIN_BIN/worktwin-list" "$@"
```

Parse the NDJSON. For any branch passed that did not appear in the output, warn that no state file matches it. For each resolved worker, you have `from_branch`, `worktree`, `task`, `commits_ahead`, `files_changed`, `uncommitted` already computed.

Skip any worker with `commits_ahead == 0` (silent skip with a one-line note in the final table).

Do not ask the user how to handle uncommitted changes. Workers are expected to commit before they stop, and the `CLAUDE.md` rules block tells them so explicitly. If a worker still has uncommitted changes, note it in the final table with a `dirty` flag in the Status column and ship whatever is already committed on that branch. Do not commit on the worker's behalf, do not pause and ask the user; the user invoked this command to push and open PRs, do that.

## 4. Conflict detection between the shipped subset

File-level overlap is a weak signal. Compute it from `git diff --name-only` per pair only as a heads-up, never as a blocker.

Real conflicts come from a simulated merge. For each pair of branches in the subset:

```bash
git merge-tree --write-tree --merge-base="$FROM_REF" "$BRANCH_A" "$BRANCH_B" 2>&1 \
  | grep -q '<<<<<<<' && echo "real conflict" || echo "clean"
```

Flag as blocking only when the output contains `<<<<<<<`.

## 5. Push and PRs

Pick the remote:

```bash
REMOTE=$(git remote | grep -x origin || git remote | head -n1)
[ -z "$REMOTE" ] && { echo "ERROR: no git remote configured" >&2; exit 1; }
```

Check `gh`:

```bash
gh --version >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
```

For each worker:

1. `git push "$REMOTE" "<branch>"`.
2. If `gh` is available:

   ```bash
   PR_NUM=$(gh pr list --head "<branch>" --json number --jq '.[0].number // empty')
   ```

   - Empty: open a new draft PR with `gh pr create --base "<from_branch>" --head "<branch>" --title "<title>" --body "<body>" --draft`.
   - Set: update with `gh pr edit "$PR_NUM" --title "<title>" --body "<body>"`. Optionally add a short comment summarising new commits.

3. If `gh` is missing or unauthenticated, print the manual `git push` and `gh pr create` commands for the user and skip the PR step for that branch.

## 6. Draft the PR title and body

Do not use a fixed template. Read:

- The full commit list (`git log <from>..<branch>`, with bodies)
- The diff (`git diff <from>..<branch>`)
- The task from the state file
- The repository's `CONTRIBUTING.md` if present
- The last 20 base-branch commit messages (`git log <from_branch> -20 --format='%s'`) to match repo conventions

Then write a title that follows what you observed (conventional commits, ticket prefixes, plain English, whatever the repo uses) and a body that explains what changed and why, with a short bullet list of notable commits or files, and any caveats.

Keep it tight. Two or three short paragraphs plus a bullet list is usually enough.

End the body with a single trailing line: `Opened by worktwin.`

## 7. Cleanup after successful ship

Shipping is the worker's terminal event. As soon as a worker is shipped successfully, it should disappear from `/worktwin-status`: the worktree directory is removed and the state file in `parallel/` is deleted. The remote branch and the open PR are untouched, so the work itself is preserved on GitHub.

Run cleanup for each worker that satisfies ALL of these:

- Push succeeded
- PR was either created or updated (or, if `gh` was unavailable, the user got the manual commands)
- The worker was clean (`uncommitted == 0`)

Do not clean up:

- Workers with `commits_ahead == 0` that were skipped (nothing happened, nothing to undo)
- Workers with `dirty` status (uncommitted changes would be lost on `git worktree remove`)
- Workers where the push or PR step errored out (the user may want to retry)

For each worker that passes the gate:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not delete the branch. The branch lives on the remote with an open PR; deleting it locally is fine when `git worktree remove` cleans up the working copy, but you do not need to touch refs/heads explicitly.

If the user later wants to keep iterating on the same branch, they can spawn it again with `/worktwin <from> <branch> "..."` and worktwin will reattach the existing branch in a fresh worktree.

If the user wants to push and open a PR without losing the worktree (e.g. they expect to iterate again before the PR is reviewed), they should run `/worktwin-finalize` instead: that command produces the same PR draft and the same push command but never touches the local state.

## 8. Final table

Recap only the shipped subset:

```
| Branch | Base | Commits | Files | PR | Conflict | Status | Cleaned |
```

- PR: PR number, or `manual` if `gh` was not used, or `skipped (no commits)` for workers with nothing ahead.
- Conflict: `clean`, `files overlap`, or `blocking`.
- Status: `clean` when the working tree was empty, or `dirty (N uncommitted)` when the worker left a non-empty working tree behind. Dirty is reportable, not blocking; the committed work shipped, the uncommitted tail did not.
- Cleaned: `yes` if the worktree and state file were removed after a successful ship, `no (<reason>)` otherwise (dirty, no commits, push or PR error).
