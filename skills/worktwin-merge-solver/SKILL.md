---
name: worktwin-merge-solver
description: Resolve sibling-vs-sibling conflicts between two or more worktwin worker branches that all want to land into the same target base branch. Detects whether branch A and branch B will collide WITH EACH OTHER when merged sequentially into the base (via `git merge-tree --merge-base=<base> A B`), reads each worker's WORKTWIN.md, task, commits, and per-file diff to understand intent, proposes per-file resolutions, dialogues with the user, and emits a single combined PR per conflicting group.
argument-hint: "<branch> [<branch> ...]   in the order you want them merged"
arguments: [branches]
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Bash(jq *), Bash(ls *), Bash(test *), Bash(cat *), Bash(grep *), Read, Write, Edit
---

# worktwin-merge-solver

Resolve sibling-vs-sibling PR conflicts for a set of worktwin worker branches.

## TL;DR — what this command checks (read this first, do not improvise)

**What it checks**: do two or more worker branches that all want to land into the **same base** (their `from_branch`) collide **with each other** when merged sequentially into that base?

**What it does NOT check**: whether any single branch conflicts with its base. That is the wrong question — every individual branch is, by construction, a clean fast-forward of its base. Asking `git diff branch..base` is meaningless here; the right question is `git merge-tree --merge-base=<base> A B`, which the `discover` subcommand below already runs for you. Trust its output, do not re-derive it.

Concrete example: `feat/dark-toggle` and `feat/branding` both target `main`. The solver asks: "if `feat/dark-toggle` lands first and then `feat/branding` tries to land, will git's three-way merge produce conflict markers?". If yes → conflicting group, resolve. If no → both PRs can be merged independently; nothing for the solver to do.

If after running `discover` the output reports `status: clean` or `status: alone` for every group, the answer is **genuinely** nothing to solve — do not second-guess by running other checks. Move on.

## How the work flows

The mechanical work runs through `bin/worktwin-merge-solver` (subcommands `discover`, `prepare`, `merge-step`, `finalize-step`, `push`, `open-pr`, `close-original`). Your job is to read the JSON it emits, walk the user through each conflicting group, write the actual conflict resolutions in files, and confirm the destructive steps (push, PR open, original PR closing) with the user before doing them.

## 0. Inputs and ordering

Branch arguments are positional and **order matters**. The order is the user's preference for who "leads" when the agent's own conflict resolution is ambiguous (you can still override per file based on context). Pass the args through verbatim to `discover`.

If no arguments are given, stop with:

```
worktwin-merge-solver needs at least one branch. List the worktwin worker branches you want me to analyse, in your preferred merge order.
```

## 1. Locate the bin directory

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
```

## 2. Discover and report

This is the single source of truth for "do these branches conflict?". Run it once with the user's branches, parse the JSON, trust the verdict.

```bash
"$WORKTWIN_BIN/worktwin-merge-solver" discover "$@"
```

Under the hood it groups the input branches by their `from_branch` and, for every group with two or more branches, runs `git merge-tree --merge-base=<base> A B` pairwise. That is exactly the sibling-vs-sibling collision check. Do not run your own `git diff`, `git log`, or other side checks before reading the result; they answer the wrong question.

Parse the JSON. Keys: `input_order`, `workers`, `groups`, `missing`.

- If `missing` is non-empty, list the names with: "no state file matched these branches — they are not currently registered worktwin workers". Continue with what was resolved.
- For each `group`, print one summary block:
  - **`status == "alone"`** (singleton in this run, no siblings against the same base): `<branch> targets <base> alone in this set. Nothing to do here.`
  - **`status == "clean"`** (multiple siblings, no real conflict): `<count> branches target <base> with no conflicts. Each PR can be reviewed and merged independently.` Skip this group; do not combine clean siblings.
  - **`status == "conflicting"`**: print the pairs and the files. Example: `<base>: feat/login and feat/profile conflict on src/auth.ts, src/user.ts.`

If no group is `conflicting`, print `nothing to solve - all PRs are already independently mergeable` and stop.

## 3. Per-group dialogue

For each `conflicting` group, in the order they appear:

### 3.1 Read both intents

For every child in `group.children`:

- Read `worker.worktwin_md` (path is given in the JSON) — the task and bound-branch context the worker was operating under.
- Print a one-line summary: `<branch>: "<task>" (N commits, M files changed)`.

### 3.2 Read each conflicting file

For each conflict file in the group, before proposing anything:

- Get the base content: `git show <group.base_ref>:<file>` (may not exist if the file is added on both sides).
- Get each side's current content: `git show <child.branch>:<file>` per child that touched it.
- Get each side's diff for that file: `git diff <group.base_ref>..<child.branch> -- <file>` per child.

This is the context you need to write a real, intent-aware resolution, not a syntactic merge.

### 3.3 Propose a resolution

For each conflicting file, write a short proposal block (3-6 lines max) that says, in plain English:

- What each side was trying to do at that location (from the task and the diff).
- Whether the intents are compatible. If yes, **what the merged version will look like and why** (e.g. "keep feat/login's added validation block, but inside feat/profile's restructured user object"). If no, say so and propose either picking one side with reasoning or splitting the change.
- If the user gave a preference order and the intents are equally good, prefer the earlier branch.

After all the per-file proposals for the group, ask:

```
proposed resolution above for <base>: <child1> + <child2> [+ <child3>...].
say `go` to apply as proposed, or override per file:
  `prefer <branch> on <file>`   - take that side verbatim
  `keep both on <file>`          - concatenate both changes (when safe)
  `skip group`                   - leave this group untouched
  `rename combined <name>`       - pick a custom combined branch name
  free-form preferences also fine.
```

Wait for the user. Update the per-file plan according to their answers and confirm: `applying as: <one-line recap>. ok? (yes/no)`.

If they say no or skip, move to the next group.

### 3.4 Prepare the combined worktree

```bash
"$WORKTWIN_BIN/worktwin-merge-solver" prepare "<base>" "<child1>" "<child2>" [...] [--name="<custom>"]
```

Capture `combined_branch`, `combined_worktree`, `base_ref` from the JSON.

The combined worktree is freshly created at `origin/<base>` so any upstream changes already merged into the base since the workers spawned are inherited automatically. That is the "one click away" guarantee.

### 3.5 Merge each child in the user-given order

For each child in order:

1. ```bash
   "$WORKTWIN_BIN/worktwin-merge-solver" merge-step "<combined_worktree>" "<child>"
   ```
   Parse the JSON. If `status == "clean"`, skip to finalize-step.
2. If `status == "conflict"`: the worktree now has unmerged files (git merge in progress, no commit yet). For each path in `conflicting_files`:
   - Read the file with conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`).
   - Apply the resolution you proposed in step 3.3. Use the Edit tool to write the resolved content — strip all conflict markers, leave no leftovers.
   - If the proposal needs adjustment based on what you see, do it and note the change in your final summary.
3. ```bash
   "$WORKTWIN_BIN/worktwin-merge-solver" finalize-step "<combined_worktree>" \
     --message="merge: <child> into <combined_branch>

   <one or two lines summarising what was resolved>"
   ```
   This refuses to commit if any conflict marker is left, so a clean exit means you got them all.

Repeat for the next child. Each child becomes a real merge commit on the combined branch.

### 3.6 Draft the combined PR

For the combined PR title and body, synthesise from all children:

- Read each child's commits with `git log <base_ref>..<child.branch>` and diff with `git diff <base_ref>..<child.branch>`.
- Read each child's `WORKTWIN.md` task.
- Read the repo's `CONTRIBUTING.md` if present and the last 20 base commit messages (`git log <base_ref> -20 --format='%s'`) to match the project's conventions.
- Title: combine the children's scopes. Example: `feat(auth+profile): combined login validation and profile rename`.
- Body: short intro explaining the combine, then one section per child child with its intent and what it contributed, then a short "resolution notes" section listing any file where you made a non-trivial choice, then the trailing line `Opened by worktwin-merge-solver.`

Ask the user: `here is the draft PR title and body — ok to push and open, or do you want edits?`

### 3.7 Push and open the PR

After user `go`:

```bash
"$WORKTWIN_BIN/worktwin-merge-solver" push "<combined_worktree>"
"$WORKTWIN_BIN/worktwin-merge-solver" open-pr "<combined_worktree>" \
  --base="<base>" --title="<title>" --body="<body>"
```

Capture the returned PR number.

### 3.8 Close the originals (with explicit confirmation)

List the original PR numbers (if known). For each child that was shipped previously, you can find its PR with:

```bash
gh pr list --head "<child.branch>" --json number --jq '.[0].number // empty'
```

Print:

```
the combined PR #<N> superseded these originals: #<a>, #<b>[, #<c>].
close them as "superseded by #<N>" now? (yes/no)
```

Only on explicit yes:

```bash
"$WORKTWIN_BIN/worktwin-merge-solver" close-original "<pr-a>" "<pr-b>" [...] \
  --superseded-by="<N>"
```

If the user says no, leave them open and tell them they can close them later from the GitHub UI.

## 4. Per-group recap

After each group is done (combined or skipped), print one line:

```
<base>: combined #<N> from <child1> + <child2>; originals #<a>, #<b> closed
```

or:

```
<base>: skipped on user request
```

## 5. Final table

At the end recap all groups handled this run:

```
| Base | Children | Status                        | Combined PR | Originals |
```

End the output with a one-line footer:

```
worktrees and state files preserved. run /worktwin-clear <branch> per worker when fully retired.
```

## Hard rules

- Never force-push. The combined branch is created fresh; if `push` fails because something already exists at that ref on the remote, surface the error and let the user decide — do not retry with `--force`.
- Never close an original PR without an explicit yes for that step in step 3.8.
- Never modify the children's own worktrees. All edits happen in the combined worktree only.
- If `discover` reports `status == "clean"` for a group, do not synthesise a combined PR for it. Clean siblings stay independent.
- Never delete the combined worktree on success. The user may want to iterate. Removal is their call via `/worktwin-clear` or a manual `git worktree remove`.
