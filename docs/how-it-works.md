# How worktwin works

## git worktree in 30 seconds

A git worktree is a second checkout of the same repository, tied to a different branch, that shares the same object store. Two worktrees of the same repo see the same history, the same remotes, and the same commits, but they have independent working directories and independent active branches. Editing a file in one worktree does not touch the other.

That solves filesystem isolation. It does not solve agent behaviour: nothing stops a Claude Code session in worktree A from running `git checkout other-branch` and stomping on worktree B's work. worktwin closes that gap.

## Lifecycle

```
/worktwin main feat/x "do thing"
   |
   v
[main repo]----------------+
   |  share .git           |
   |                       v
   |             [worktree feat/x]
   |             |  CLAUDE.md (rules)
   |             |  task code...
   v             v
[shared .git/parallel/feat-x.json]   <-- state, visible from every worktree

iterate in chat -> commits land on feat/x

ship one:   /worktwin-ship feat/x         -> git push + gh pr for feat/x
ship many:  /worktwin-ship-all            -> git push + gh pr for every worker
local only: /worktwin-finalize [<branch>] -> report + draft, no network
   |
   v
optional cleanup: git worktree remove, remove state file
```

## State file

Path: `$(git rev-parse --git-common-dir)/parallel/<branch-slug>.json`.

`--git-common-dir` always points at the main repo's `.git` directory, even when called from inside a worktree (where `.git` is a redirect file). Using it guarantees every worker writes to the same place and the ship and finalize commands can discover them from any worktree.

The slug is derived from the branch name by replacing every character outside `[a-zA-Z0-9._-]` with a dash. The branch itself is not renamed.

Fields:

```json
{
  "branch": "feat/x",
  "from_branch": "main",
  "worktree": "/abs/path/to/repo--feat-x",
  "task": "do thing",
  "started_at": "2026-06-09T19:30:00Z",
  "status": "active"
}
```

The state file is local to the machine. It is not committed and is not synced via `git push`. This is intentional: parallel work sessions belong to the developer, not the repo.

## Why the rules go into CLAUDE.md

The text the skill injects into the live context lasts only until the next `/compact`. After compaction Claude Code summarises the conversation and the original skill text is gone. A new Claude Code session opened in the same worktree starts with no context at all.

A `CLAUDE.md` file at the root of a working directory is auto-loaded by Claude Code on every session and is re-read after compaction. By writing the rules block into the worktree's `CLAUDE.md`, worktwin makes the binding persistent: any future session, including ones the user opens manually a week later, picks up the worker rules without re-running `/worktwin`.

The block is delimited:

```
<!-- BEGIN worktwin -->
... rules ...
<!-- END worktwin -->
```

If the worktree already has a `CLAUDE.md`, worktwin only touches the marked block. Running `/worktwin` again on the same branch replaces the block in place.

## Conflict detection

`/worktwin-ship` and `/worktwin-ship-all` use a two-level model:

1. File-level overlap (`comm` on the two file lists). A weak signal: two branches editing different parts of the same file are not in conflict. Shown as informational.
2. Real conflicts from `git merge-tree --write-tree --merge-base=<base> <a> <b>`. If the output contains `<<<<<<<`, the merge would actually conflict. Shown as blocking.

Step 2 requires git 2.38 or later.

## Known limitations

- State is local, not portable across machines or via `git push`. By design.
- `gh` integration assumes GitHub. GitLab and Bitbucket are not supported in v0.1.
- The rules block in `CLAUDE.md` lives at the root of the worktree only. Nested `CLAUDE.md` files are not modified.
- The branch name sanitiser rewrites the worktree folder name, not the branch. Folders like `repo--feat-foo-bar` may differ visually from the branch `feat/foo bar`.
