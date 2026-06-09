# bin/ scripts

The deterministic part of worktwin lives in `bin/`. The skills are thin orchestrators that call these scripts and let the agent handle judgement (drafting PR content, deciding on warnings, formatting tables). The scripts are pluggable: anything you can do from a worktwin skill, you can also do from a shell directly.

Every script ships in two flavours that follow the same contract:

| script | bash | PowerShell |
|---|---|---|
| `worktwin-init` | `bin/worktwin-init` | `bin/worktwin-init.ps1` |
| `worktwin-claude-md` | `bin/worktwin-claude-md` | `bin/worktwin-claude-md.ps1` |
| `worktwin-list` | `bin/worktwin-list` | `bin/worktwin-list.ps1` |

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

Write or update the worktwin rules block in a worktree's `CLAUDE.md`, between explicit markers. Idempotent.

```
worktwin-claude-md <worktree-path> <branch> <from-branch> "<task>"
```

The block is delimited by `<!-- BEGIN worktwin -->` and `<!-- END worktwin -->`. Existing blocks are replaced in place. Content outside the markers is preserved verbatim. If no `CLAUDE.md` exists yet, one is created with just the block.

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

## Composition example

A small shell pipeline that lists every worker with at least one commit ahead and uncommitted changes still on disk:

```bash
worktwin-list | jq -c 'select(.commits_ahead > 0 and .uncommitted > 0)'
```

The same data, formatted as a table, on PowerShell:

```powershell
.\worktwin-list.ps1 | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.uncommitted -gt 0 } | Format-Table branch, commits_ahead, uncommitted
```
