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

## 5. Optional cleanup

After PRs are open or updated, ask once at the end whether to clean up every shipped worker:

```bash
git worktree remove "<worktree>"
rm "$(git rev-parse --git-common-dir)/parallel/<slug>.json"
```

Do not auto-delete branches.

## 6. Final table

Recap every shipped worker:

```
| Branch | Base | Commits | Files | PR | Conflict | Status |
```

- PR: PR number, or `manual` if `gh` was not used, or `skipped (no commits)` for workers with nothing ahead.
- Conflict: `clean`, `files overlap`, or `blocking`.
- Status: `clean` when the working tree was empty, or `dirty (N uncommitted)` when the worker left a non-empty working tree behind. Dirty is reportable, not blocking; the committed work shipped, the uncommitted tail did not.
