---
name: worktwin-ship
description: Discover all active worktwin workers, summarize their changes, detect real cross-branch conflicts, push branches, and open or update GitHub pull requests. Use at the end of a parallel work session to ship everything.
argument-hint: "[branch1 branch2 ...]   leave empty to auto-detect all active workers"
arguments: [branches]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(cat *), Bash(ls *), Bash(find *), Bash(mkdir *), Bash(echo *), Bash(comm *), Bash(sort *), Bash(jq *), Bash(grep *), Read
---

# worktwin-ship

Coordinate the end of a parallel work session: collect every active worker, surface real conflicts, push branches, and open or update PRs.

## 1. Discovery

State files live in the shared git directory, not in the per-worktree `.git`:

```bash
PARALLEL_DIR="$(git rev-parse --git-common-dir)/parallel"
```

If `$PARALLEL_DIR` exists, read every `*.json` file inside it. Each file describes one worker: `branch`, `from_branch`, `worktree`, `task`, `started_at`, `status`.

If the directory does not exist or is empty, fall back to `git worktree list --porcelain` and infer workers from any worktree whose branch differs from the main checkout.

If the user passed branch names as arguments, restrict the set to only those.

## 2. Per-worker summary

For each worker collect:

- `git log <from_branch>..<branch> --oneline` (commits ahead)
- `git diff --name-status <from_branch>..<branch>` (files changed)
- Commit count and file count

Print one section per worker. Skip workers with zero commits ahead and tell the user.

## 3. Conflict detection

File-level overlap (from `comm` on the two file lists) is a weak signal: two branches editing different parts of the same file are not in conflict. Use it only as a heads-up.

Real conflicts come from a simulated merge. For every pair of branches with overlapping files, run:

```bash
git merge-tree --write-tree --merge-base="$FROM_REF" "$BRANCH_A" "$BRANCH_B" 2>&1 \
  | grep -q '<<<<<<<' && echo "real conflict" || echo "clean"
```

Only flag the pair as a blocking conflict when the merge-tree output contains conflict markers. Show the user the relevant diff and suggest a resolution order. Otherwise just note the file overlap as informational.

## 4. Push and pull requests

Pick the remote (prefer `origin`, fall back to the first configured remote):

```bash
REMOTE=$(git remote | grep -x origin || git remote | head -n1)
[ -z "$REMOTE" ] && { echo "ERROR: no git remote configured"; exit 1; }
```

Check whether `gh` is available and authenticated:

```bash
gh --version >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
```

For each worker with commits ahead:

1. Ask the user to confirm the push.
2. `git push "$REMOTE" "<branch>"`.
3. If `gh` is available, check for an existing PR:

   ```bash
   PR_NUM=$(gh pr list --head "<branch>" --json number --jq '.[0].number // empty')
   ```

   - If empty: open a new draft PR. `gh pr create --base "<from_branch>" --head "<branch>" --title "<task>" --body "<body>" --draft`
   - If set: update the existing PR. `gh pr edit "$PR_NUM" --body "<refreshed body>"`. Optionally add a comment summarising the new commits.

   PR body must include: the task description, the commit list, the file change list, and a footer noting the PR was opened by worktwin.

4. If `gh` is missing or unauthenticated, print the manual commands the user should run and skip the PR step for that branch.

## 5. Optional cleanup

After PRs are open or updated, ask the user whether to clean up each worker. For confirmed ones:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not auto-delete the branch. Mention that `git branch -d "<branch>"` is safe only after the PR is merged.

## 6. Final table

End with a single recap table:

```
| Branch | Base | Commits | Files | PR | Conflict |
```

One row per worker. PR column shows the PR number or "manual" if `gh` was not used. Conflict column shows "clean", "files overlap", or "blocking" based on step 3.
