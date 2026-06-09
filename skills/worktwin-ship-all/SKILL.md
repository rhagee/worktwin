---
name: worktwin-ship-all
description: Push and open or update GitHub pull requests for every active worktwin worker on the current repository. Use at the end of a session when everything is ready to go out together. Takes no arguments.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(cat *), Bash(ls *), Bash(find *), Bash(mkdir *), Bash(echo *), Bash(comm *), Bash(sort *), Bash(jq *), Bash(grep *), Read
---

# worktwin-ship-all

Ship every active worker on this repository in one go. Same behaviour as `/worktwin-ship`, except the worker list is discovered automatically instead of passed in.

## 1. Discover all workers

```bash
PARALLEL_DIR="$(git rev-parse --git-common-dir)/parallel"
```

Read every `*.json` file in `$PARALLEL_DIR`. Each one is a worker: `branch`, `from_branch`, `worktree`, `task`, `started_at`, `status`.

If the directory does not exist or is empty, fall back to `git worktree list --porcelain` and infer workers from any worktree whose branch differs from the main checkout.

If nothing is found, print `no active worktwin workers, nothing to ship` and stop.

## 2. Confirm scope with the user

Before doing anything destructive, list the workers you found and ask the user to confirm shipping the full set. If they want a subset, tell them to use `/worktwin-ship <branch>` instead.

## 3. Per-worker summary, conflict detection, push, PR

Follow the same steps as `/worktwin-ship` (sections 3 through 6 of that skill):

- Collect commit list, diff, file count for each worker.
- Pairwise real conflict detection with `git merge-tree --write-tree`. File overlap from `comm` stays as a weak informational signal.
- Pick the remote, check `gh` availability.
- For each worker with commits ahead: push, then create or update the PR. Drafts only.
- Draft the PR title and body per worker by actually reading the commits, the diff, the task, and the repo's conventions (`CONTRIBUTING.md`, recent commit messages). No fixed template. End the body with `Opened by worktwin.`.
- If `gh` is missing or unauthenticated, print manual commands and skip the PR step for that branch.

## 4. Optional cleanup

Ask once at the end whether to clean up every shipped worker, or do it per-worker if the user prefers granular control:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not auto-delete branches.

## 5. Final table

Recap every shipped worker:

```
| Branch | Base | Commits | Files | PR | Conflict |
```

PR column shows the PR number or `manual`. Conflict column shows `clean`, `files overlap`, or `blocking`.
