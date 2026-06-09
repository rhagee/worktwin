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

## 3. Ship without asking

The user invoked `/worktwin-ship-all` deliberately. Do not ask them to confirm the scope, do not ask them to pick a subset, do not ask them what to do about uncommitted changes. Workers are responsible for committing before they hand control back, and the `CLAUDE.md` rules block makes that explicit. If a worker still has uncommitted changes when ship-all runs, note it in the final table with a `dirty` flag in the Status column and ship whatever is already committed on that branch. Do not try to commit on the worker's behalf.

Print one short line announcing what you are about to do (e.g. `shipping 3 workers ...`) and proceed straight to step 4.

## 4. Per-worker work

Apply the same per-worker steps as `/worktwin-ship`:

- Skip workers with `commits_ahead == 0` (silent skip with a one-line note in the final table)
- Pairwise real conflict detection with `git merge-tree --write-tree`
- Pick the remote (prefer `origin`)
- Check `gh` availability
- Push each branch, then create or update its draft PR
- Draft the PR title and body per worker by reading commits, diff, task, and repo conventions (`CONTRIBUTING.md`, last 20 base-branch commit messages). No fixed template. End the body with `Opened by worktwin.`
- If `gh` is missing or unauthenticated, print manual commands and skip the PR step

## 5. Cleanup after successful ship

Shipping is the worker's terminal event. Each worker that ships successfully is removed from local state so it stops appearing in `/worktwin-status`. The remote branch and the open PR are not touched; the work is safe on GitHub.

For each worker, run cleanup only when ALL of these hold:

- Push succeeded
- PR was either created or updated (or the manual commands were printed because `gh` was unavailable)
- The worker was clean (`uncommitted == 0`)

Skip cleanup for workers that:

- Were skipped because `commits_ahead == 0` (nothing happened, nothing to undo)
- Have `dirty` status (uncommitted changes would be lost on `git worktree remove`)
- Errored during push or PR creation

For each worker that passes the gate:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not ask the user. The cleanup is part of "shipping is done", not a separate question.

If the user wants to push and open a PR without losing the worktree, they should use `/worktwin-finalize` instead: that command produces the same PR draft and the same push command but never touches the local state.

## 6. Final table

Recap every shipped worker:

```
| Branch | Base | Commits | Files | PR | Conflict | Status | Cleaned |
```

- PR: PR number, or `manual` if `gh` was not used, or `skipped (no commits)` for workers with nothing ahead.
- Conflict: `clean`, `files overlap`, or `blocking`.
- Status: `clean` when the working tree was empty, or `dirty (N uncommitted)` when the worker left a non-empty working tree behind. Dirty is reportable, not blocking; the committed work shipped, the uncommitted tail did not.
- Cleaned: `yes` if the worktree and state file were removed after a successful ship, `no (<reason>)` otherwise (dirty, no commits, push or PR error).
