---
name: worktwin-ship
description: Push and open or update GitHub pull requests for one or more specific worktwin workers. Use when a subset of parallel workers are done and you want to ship them without touching the others. Requires at least one branch argument.
argument-hint: <branch> [<branch> ...]
arguments: [branches]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(cat *), Bash(ls *), Bash(find *), Bash(mkdir *), Bash(echo *), Bash(comm *), Bash(sort *), Bash(jq *), Bash(grep *), Read
---

# worktwin-ship

Ship the specific worktwin workers the user passed as arguments. Push their branches, open or update a pull request for each, and report.

## 1. Require explicit branches

If no branch argument was passed, stop immediately with:

```
worktwin-ship requires at least one branch. Use /worktwin-ship <branch> or /worktwin-ship-all.
```

Do not auto-detect. The whole point of this command is to ship a subset.

## 2. Resolve each branch to a worker

State files live in the shared git directory:

```bash
PARALLEL_DIR="$(git rev-parse --git-common-dir)/parallel"
```

For each branch argument, look up the matching `*.json` file in `$PARALLEL_DIR` (slug-match against the branch name). If a branch has no state file, warn and skip it.

## 3. Per-worker summary

For each resolved worker, collect:

- `git log <from_branch>..<branch> --oneline`
- `git diff --name-status <from_branch>..<branch>`
- Commit count and file count

Skip workers with zero commits ahead and tell the user.

## 4. Conflict detection between the shipped subset

File-level overlap from `comm` is a weak signal: two branches editing different sections of the same file are not a real conflict. Use it only as a heads-up.

Real conflicts come from a simulated merge. For each pair of branches in the shipped subset that share files, run:

```bash
git merge-tree --write-tree --merge-base="$FROM_REF" "$BRANCH_A" "$BRANCH_B" 2>&1 \
  | grep -q '<<<<<<<' && echo "real conflict" || echo "clean"
```

Only flag as blocking when the output contains conflict markers.

## 5. Push and pull requests

Pick the remote (prefer `origin`, fall back to the first configured remote):

```bash
REMOTE=$(git remote | grep -x origin || git remote | head -n1)
[ -z "$REMOTE" ] && { echo "ERROR: no git remote configured"; exit 1; }
```

Check `gh` availability:

```bash
gh --version >/dev/null 2>&1 && gh auth status >/dev/null 2>&1
```

For each worker with commits ahead:

1. Confirm the push with the user.
2. `git push "$REMOTE" "<branch>"`.
3. If `gh` is available, check for an existing PR:

   ```bash
   PR_NUM=$(gh pr list --head "<branch>" --json number --jq '.[0].number // empty')
   ```

   - If empty: open a new draft PR with `gh pr create --base "<from_branch>" --head "<branch>" --title "<title>" --body "<body>" --draft`.
   - If set: update with `gh pr edit "$PR_NUM" --title "<title>" --body "<body>"`. Add a short comment summarising the new commits if any landed since last ship.

4. If `gh` is missing or unauthenticated, print the manual `git push` and `gh pr create` commands the user should run, then skip the PR step for that branch.

## 6. Drafting the PR title and body

Do not use a fixed template. The agent that runs this command has visibility into the actual work and should draft a real PR title and body, the way a developer would.

For each worker, read:

- The full commit list (`git log <from>..<branch>`), not just `--oneline`, to see commit message bodies.
- The diff (`git diff <from>..<branch>`) for the substance of the change.
- The original task from the state file.
- The repository's `CONTRIBUTING.md` if present, and the last 20 commit messages on the base branch (`git log <from_branch> -20 --format='%s'`), to match the project's tone and conventions.

Then write:

- A title that follows the conventions you observed (conventional commits, ticket prefixes, plain English, whatever the repo uses).
- A body that explains what changed and why, with a brief bullet list of notable commits or files, and any caveats the user should know before merging.

Keep it tight. PRs do not need essays. Two or three short paragraphs plus a bullet list is usually enough.

Add a single trailing line at the end of the body: `Opened by worktwin.` Nothing else.

## 7. Optional cleanup

After PRs are open or updated, ask the user whether to clean up the shipped workers:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not auto-delete the branch. Mention that `git branch -d "<branch>"` is safe only after the PR is merged.

## 8. Final table

End with a single recap table for the shipped subset only:

```
| Branch | Base | Commits | Files | PR | Conflict |
```

PR column shows the PR number or `manual` if `gh` was not used. Conflict column shows `clean`, `files overlap`, or `blocking`.
