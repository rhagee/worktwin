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

Skip any worker with `commits_ahead == 0` and tell the user.

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

1. Confirm the push with the user.
2. `git push "$REMOTE" "<branch>"`.
3. If `gh` is available:

   ```bash
   PR_NUM=$(gh pr list --head "<branch>" --json number --jq '.[0].number // empty')
   ```

   - Empty: open a new draft PR with `gh pr create --base "<from_branch>" --head "<branch>" --title "<title>" --body "<body>" --draft`.
   - Set: update with `gh pr edit "$PR_NUM" --title "<title>" --body "<body>"`. Optionally add a short comment summarising new commits.

4. If `gh` is missing or unauthenticated, print the manual `git push` and `gh pr create` commands for the user and skip the PR step for that branch.

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

## 7. Optional cleanup

After PRs are open or updated, ask the user whether to clean up the shipped workers:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not auto-delete the branch.

## 8. Final table

Recap only the shipped subset:

```
| Branch | Base | Commits | Files | PR | Conflict |
```

PR column shows the PR number or `manual`. Conflict column shows `clean`, `files overlap`, or `blocking`.
