---
name: worktwin-ship-all
description: Push and open or update GitHub pull requests for every active worktwin worker on the current repository. Use at the end of a session when everything is ready to go out together. Accepts a --draft flag to open PRs in draft mode.
argument-hint: '[--draft]'
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(ls *), Bash(test *), Bash(jq *), Bash(grep *), Read
---

# worktwin-ship-all

Ship every active worker in one go. Same workflow as `/worktwin-ship`, but the worker set is discovered instead of passed in.

## 0. Parse the optional --draft flag

Check `$@` for `--draft`. If present, every PR opened in this run is a draft. Default (no flag) opens normal PRs. Existing PRs are not converted between draft and ready states.

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
- Push each branch, then create or update its PR. New PRs are normal unless the `--draft` flag was set in step 0, in which case append `--draft` to `gh pr create`. Existing PRs are updated in place without touching their draft state.
- Draft the PR title and body per worker by reading commits, diff, task, and repo conventions (`CONTRIBUTING.md`, last 20 base-branch commit messages). No fixed template. End the body with `Opened by worktwin.`
- If `gh` is missing or unauthenticated, print manual commands and skip the PR step. Include `--draft` in the printed command when the flag was set.

## 5. Preserve local state

Shipping is *not* the worker's terminal event. The worktrees and state files are deliberately kept on disk after a successful ship so workers can be reused — by `/worktwin-merge-solver` (which needs the worktrees and their `WORKTWIN.md` context to resolve cross-PR conflicts) or by the user to iterate further on a branch without re-spawning.

Do not remove worktrees. Do not delete state files. Do not delete branches. The remote branches and open PRs are independent of local state.

When the user is truly done with a worker, they run `/worktwin-clear <branch>` themselves.

## 6. Final table

Recap every shipped worker:

```
| Branch | Base | Commits | Files | PR | Conflict | Status |
```

- PR: PR number, or `manual` if `gh` was not used, or `skipped (no commits)` for workers with nothing ahead.
- Conflict: `clean`, `files overlap`, or `blocking`.
- Status: `clean` when the working tree was empty, or `dirty (N uncommitted)` when the worker left a non-empty working tree behind. Dirty is reportable, not blocking; the committed work shipped, the uncommitted tail did not.

End the output with a one-line footer:

```
worktrees preserved. run /worktwin-merge-solver <branches...> to resolve cross-PR conflicts, or /worktwin-clear <branch> when a worker is fully retired.
```
