# bin/ scripts

The deterministic part of worktwin lives in `bin/`. The skills are thin orchestrators that call these scripts and let the agent handle judgement (drafting PR content, deciding on warnings, formatting tables). The scripts are pluggable: anything you can do from a worktwin skill, you can also do from a shell directly.

Every script ships in two flavours that follow the same contract:

| script | bash | PowerShell |
|---|---|---|
| `worktwin-init` | `bin/worktwin-init` | `bin/worktwin-init.ps1` |
| `worktwin-claude-md` | `bin/worktwin-claude-md` | `bin/worktwin-claude-md.ps1` |
| `worktwin-list` | `bin/worktwin-list` | `bin/worktwin-list.ps1` |
| `worktwin-clear` | `bin/worktwin-clear` | `bin/worktwin-clear.ps1` |
| `worktwin-merge-solver` | `bin/worktwin-merge-solver` | `bin/worktwin-merge-solver.ps1` |

After install they land at:

- `~/.claude/skills/worktwin/bin/` (global install)
- `<repo>/.claude/skills/worktwin/bin/` (local install)

Add the global path to your shell PATH if you want to call them without the full path:

```bash
export PATH="$HOME/.claude/skills/worktwin/bin:$PATH"
```

PowerShell:

```powershell
$env:PATH = "$env:USERPROFILE\.claude\skills\worktwin\bin;$env:PATH"
```

## worktwin-init

Atomic spawn of a parallel worker. Verifies the repo, sanitises the slug, resolves the source branch (with a fetch fallback for remote-only branches), creates the worktree, and writes the state file in the shared git directory.

```
worktwin-init <from-branch> <new-branch> "<task>"
```

Stdout, on success, is a JSON object:

```json
{
  "main_repo":   "/abs/path",
  "worktree":    "/abs/path--slug",
  "branch":      "<new-branch>",
  "from_branch": "<from-branch>",
  "from_ref":    "<from-branch> or origin/<from-branch>",
  "state_file":  "/abs/path/.git/parallel/slug.json",
  "warnings":    ["optional strings"]
}
```

Exit codes:

- `0` success
- `1` operational error (not a git repo, source branch missing, worktree conflict)
- `2` usage error

## worktwin-claude-md

Set up the worktwin parallel-worker context in a worktree. Writes two files and prevents both from being committed. Idempotent.

```
worktwin-claude-md <worktree-path> <branch> <from-branch> "<task>"
```

Files written:

- **`WORKTWIN.md`** — full DO/DO NOT rules, bound branch, source branch, task, and the hard-rule about never committing the worktwin context files. Always rewritten.
- **`CLAUDE.md`** — original content preserved verbatim. A small reference block delimited by `<!-- BEGIN worktwin -->` / `<!-- END worktwin -->` is appended at the **bottom**, pointing at `@WORKTWIN.md`. If no `CLAUDE.md` exists yet, one is created with just that block. An existing worktwin block anywhere in the file is stripped first, so re-runs always land the block at the bottom.

Both files are then marked so git will not stage them on `git add -A` or `git commit -a`:

- if the file is tracked in the index (e.g., a company `CLAUDE.md` inherited from the branch), `git update-index --skip-worktree` is set — the modification stays on disk but `git status` and staging ignore it
- if the file is untracked, an anchored entry (`/CLAUDE.md`, `/WORKTWIN.md`) is appended to the per-worktree `info/exclude`

The agent is also told explicitly in the appended block to warn the user before any explicit commit of either file. The original branch CLAUDE.md is therefore preserved both as content (visible to Claude Code) and as a tracked git object (untouched on the branch).

No stdout on success. Errors go to stderr. Exit codes match `worktwin-init`.

## worktwin-list

Discover every worker on the current repository. Emits NDJSON (one JSON object per line) on stdout.

```
worktwin-list                       # list all
worktwin-list feat/auth feat/pay    # filter to specific branches
```

Each line:

```json
{
  "branch":          "...",
  "from_branch":     "...",
  "worktree":        "...",
  "task":            "...",
  "started_at":      "...",
  "status":          "active",
  "worktree_exists": true,
  "commits_ahead":   3,
  "files_changed":   5,
  "uncommitted":     0
}
```

When the parallel directory is missing, exits silently with no output. Filtering by branch is silent when no matches are found, not an error.

`jq` is recommended. The bash version falls back to a simpler parser when `jq` is missing, which is fine for ASCII-only task strings but can mishandle exotic characters. The PowerShell version uses the native `ConvertFrom-Json` and `ConvertTo-Json` with no fallback needed.

## worktwin-merge-solver

Cross-PR conflict resolution. One subcommand per atomic operation; the agent layer (the skill) orchestrates them. Requires `jq` in the bash flavour.

```
worktwin-merge-solver <subcommand> [args]
```

Subcommands:

- `discover <branch> [<branch> ...]`
  Validate each branch has a worktwin state file, group by `from_branch`, run `git merge-tree --merge-base=<base>` pairwise per group, and emit JSON: `input_order`, `workers` (with `worktwin_md` path and recent `commits`), `groups` (`status`: `alone` | `clean` | `conflicting`, with conflict pairs and files per pair), and `missing` branches. Working tree is never touched.

- `prepare <base> <child> [<child> ...] [--name=<combined-branch>]`
  Create a fresh worktree off `origin/<base>` (falls back to local `<base>`) on a new branch. The default combined branch name is `worktwin-merge/<base-slug>/<child1>+<child2>[+...]`. Returns `combined_branch`, `combined_worktree`, `base_ref`, `children`.

- `merge-step <combined-worktree> <child>`
  Run `git merge --no-ff --no-commit <child>` inside the combined worktree. Emits JSON with `status` (`clean` | `conflict`) and `conflicting_files`. Use the Edit tool to write resolutions when status is `conflict`, then call `finalize-step`.

- `finalize-step <combined-worktree> --message=<commit-message>`
  Refuses to commit when any conflict marker is left (`git diff --check`). On success, stages everything and commits the merge with the given message. Returns the new HEAD `sha`.

- `push <combined-worktree> [--remote=<remote>]`
  Push the combined branch to `--remote=` (default `origin`) with `-u`.

- `open-pr <combined-worktree> --base=<base> --title=<t> --body=<f> [--draft]`
  Open a PR via `gh` from the combined branch to `<base>`. Returns the PR `url`, `number`, and `head` branch. Errors if `gh` is missing or unauthenticated.

- `close-original <pr-num> [<pr-num> ...] --superseded-by=<n>`
  Comment "Superseded by #N (combined via worktwin-merge-solver). The branch and history are preserved." on each PR, then close it via `gh`. Returns a per-PR `closed: true|false` result.

The skill `worktwin-merge-solver` ties these together: read each worker's `WORKTWIN.md` and diff, propose per-file resolutions with reasoning, dialogue with the user, then drive the subcommands in sequence and ask for explicit confirmation before push, PR open, and original-PR closing.

## worktwin-clear

Remove the state file for a stale worker (worktree gone, state lingers). Refuses to touch a worker whose worktree still exists; in that case use the ship or finalize flow, or `git worktree remove` manually.

```
worktwin-clear <branch>
```

No stdout on success beyond a one-line confirmation. Errors go to stderr.

Exit codes:

- `0` state file removed
- `1` operational error (not a git repo, branch not known, worktree still present)
- `2` usage error

## Composition example

A small shell pipeline that lists every worker with at least one commit ahead and uncommitted changes still on disk:

```bash
worktwin-list | jq -c 'select(.commits_ahead > 0 and .uncommitted > 0)'
```

The same data, formatted as a table, on PowerShell:

```powershell
.\worktwin-list.ps1 | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.uncommitted -gt 0 } | Format-Table branch, commits_ahead, uncommitted
```
