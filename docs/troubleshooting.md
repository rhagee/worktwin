# Troubleshooting

## `fatal: '<path>' already exists`

A worktree at that path is already registered. Either it is the one you want, in which case open a Claude Code session there and keep working, or it is stale and you can remove it with `git worktree remove <path>` then re-run `/worktwin`.

## The agent switched branches by accident

Open `CLAUDE.md` in the worktree root. The `<!-- BEGIN worktwin --> ... <!-- END worktwin -->` block should be present. If it is missing or empty, re-run `/worktwin` with the same arguments: it is idempotent and will restore the block.

If the block is there but the agent still drifts, mention the rules explicitly in your next message. The agent reads `CLAUDE.md` on every new turn but conversations carry weight too.

## `/worktwin-ship` says it needs a branch argument

By design. `/worktwin-ship` ships specific workers, never all of them, to prevent accidental batch-ship when only one worker is done. Pass the branches you want: `/worktwin-ship feat/auth` or `/worktwin-ship feat/auth feat/payments`. If you genuinely want every active worker, use `/worktwin-ship-all`.

## Ship or finalize reports no workers

State files live in `$(git rev-parse --git-common-dir)/parallel/`, not in `.git/parallel/`. The two are different when you call them from inside a worktree. If a worker is missing, check that path and look for the expected `*.json` file.

If the directory is empty but you know there are worktrees, fall back to `git worktree list` to find them and pass the branch names explicitly to `/worktwin-ship` or `/worktwin-finalize`.

## "task not found" but the Dev Drive auto-mount task is registered

If you check the scheduled task from a non-admin PowerShell with `Get-ScheduledTask -TaskName 'worktwin-mount-<vhd-name>'`, you may get `$null` even though the task exists. This is a Windows quirk: tasks with principal `SYSTEM` are not visible to non-admin callers, and `Get-ScheduledTask` returns no match silently rather than raising "access denied". Two ways to verify correctly from any shell:

```powershell
schtasks /query /TN 'worktwin-mount-worktwin-dev-drive'
```

Differentiate the outcomes by the error message:

- `ERRORE: Impossibile trovare il file specificato.` / `ERROR: The system cannot find the file specified.` -> the task really does not exist; the setup did not register it. Run `/worktwin-light-teardown-windows -RegisterAutoMountOnly -VhdPath <your.vhdx>` to repair.
- `ERRORE: Accesso negato.` / `ERROR: Access is denied.` -> the task exists and is registered correctly. You just cannot see it without admin. This is the normal state.

If you really need to inspect the task object, relaunch PowerShell as Administrator and `Get-ScheduledTask` will then return the full object.

## `worktwin-merge-solver` says it needs jq

The bash flavour of `worktwin-merge-solver` builds deeply nested JSON (groups, conflicts, worker contexts) and uses `jq` to keep that logic compact and correct. `jq` is a hard requirement only for that script in the bash flavour. Every other worktwin bash script has a jq-optional fallback, and the PowerShell flavour of every script (including `worktwin-merge-solver.ps1`) uses native `ConvertTo-Json` / `ConvertFrom-Json` and does not need `jq` at all.

Install jq:

| platform | command |
|---|---|
| macOS | `brew install jq` |
| Debian/Ubuntu | `sudo apt-get install jq` |
| Fedora/RHEL | `sudo dnf install jq` |
| Arch | `sudo pacman -S jq` |
| Alpine | `sudo apk add jq` |
| Windows (scoop) | `scoop install jq` |
| Windows (winget) | `winget install jqlang.jq` |
| Windows (choco) | `choco install jq` |

The error message printed by the script also includes the matching hint for the detected platform. The installer (`install.sh`) checks for jq at the end and prints the same hint if it is missing.

## `gh` is not authenticated

Run `gh auth login` once, then retry the ship command. Until then, ship will print the manual `git push` and `gh pr create` commands for you to run yourself. If you prefer to keep `gh` out of the loop entirely, use `/worktwin-finalize`: it never calls `gh` and gives you the same draft PR title and body to use however you want.

## PR already exists

`/worktwin-ship` and `/worktwin-ship-all` both check for an existing PR with `gh pr list --head <branch>` and update it with `gh pr edit` instead of failing. If you see a duplicate-PR error, your `gh` CLI may be too old. Upgrade to a recent version.

## Source branch not found

If you pass `develop` but the branch only exists on `origin`, worktwin fetches and uses `origin/develop`. If the fetch also fails, the branch genuinely does not exist anywhere reachable. Check `git branch -a` and your remote configuration.

## Branch names with unusual characters

Worktwin sanitises the branch name to derive a folder name (replacing anything outside `[a-zA-Z0-9._-]` with a dash). The branch itself is unchanged. If you see a folder named `repo--my-branch-name` for a branch called `my/branch name`, that is expected.

## The rules vanished after `/compact`

Verify `CLAUDE.md` at the worktree root still contains the worktwin block. Root `CLAUDE.md` is re-read by Claude Code after compaction; nested ones are not. If the block is gone, re-run `/worktwin` to restore it.

## Windows: which install script do I use?

Use `install.ps1` from PowerShell. The bash `install.sh` only runs from Git Bash or WSL because Windows opens `.sh` files with the default associated application (often the editor), instead of executing them.

## Windows: `running scripts is disabled on this system`

The default PowerShell execution policy blocks unsigned scripts on some machines. Two fixes:

One-time bypass for a single run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Permanent for your user (recommended, this is the default on most developer machines anyway):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Both keep the system-wide policy untouched.
