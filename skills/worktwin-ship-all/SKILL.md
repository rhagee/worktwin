---
name: worktwin-ship-all
description: Push and open or update GitHub pull requests for every active worktwin worker on the current repository. Use at the end of a session when everything is ready to go out together. Takes no arguments.
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(test *), Bash(jq *), Bash(grep *), Read
---

# worktwin-ship-all

Ship every active worker in one go. Same workflow as `/worktwin-ship`, but the worker set is discovered instead of passed in.

## 1. Locate the bin directory

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
```

## 2. Discover all workers

```bash
"$WORKTWIN_BIN/worktwin-list"
```

If the output is empty, print `no active worktwin workers, nothing to ship` and stop.

## 3. Confirm scope

List the discovered workers and ask the user to confirm shipping the full set. If they want a subset, tell them to use `/worktwin-ship <branch>` instead.

## 4. Follow the ship workflow

Apply the same per-worker steps as `/worktwin-ship`:

- Skip workers with `commits_ahead == 0`
- Pairwise real conflict detection with `git merge-tree --write-tree`
- Pick the remote (prefer `origin`)
- Check `gh` availability
- Push each branch, then create or update its draft PR
- Draft the PR title and body per worker by reading commits, diff, task, and repo conventions (`CONTRIBUTING.md`, last 20 base-branch commit messages). No fixed template. End the body with `Opened by worktwin.`
- If `gh` is missing or unauthenticated, print manual commands and skip the PR step

## 5. Optional cleanup

Ask once at the end whether to clean up every shipped worker, or do it per-worker if the user prefers:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not auto-delete branches.

## 6. Final table

Recap every shipped worker:

```
| Branch | Base | Commits | Files | PR | Conflict |
```

PR column shows the PR number or `manual`. Conflict column shows `clean`, `files overlap`, or `blocking`.
