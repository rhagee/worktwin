# worktwin

> Spawn isolated Claude Code agents on parallel branches. No conflicts, no chaos.
> Light mode: 0 disk overhead on APFS, btrfs, XFS, and Windows ReFS.

worktwin is a Claude Code skill, not a CLI tool. Install it once, invoke it inside Claude Code with `/worktwin`, and the agent configures itself to work on a dedicated branch in an isolated git worktree. Multiple sessions on the same repo, zero context bleed, and on capable filesystems each parallel worker adds near-zero bytes to disk.

<!-- TODO: replace with demo GIF -->
![demo](docs/demo.gif)

## The problem

Two Claude Code sessions, same repo, same file: chaos. Plain git worktrees give you filesystem isolation but do not tell the agent how to behave. The agent still wanders, switches branches, edits files in the other worktree, and your parallel work collapses into one tangled history.

And the disk bill: every standard worktree is a full working copy. Four parallel agents on a 70 GB monorepo eat 280 GB of duplicated files just to keep them apart.

## What worktwin does differently

| | `claude --worktree` | `gtr` (CodeRabbit) | worktwin |
|---|---|---|---|
| Creates a worktree | yes | yes | yes |
| Instructs the agent | no | no | yes |
| Tracks active workers | no | no | yes |
| Real conflict detection (not just file overlap) | no | no | yes |
| Pushes branches and opens or updates PRs | no | no | yes |
| Iterates in the same chat | no | no | yes |
| 0 disk overhead per worker (light mode) | no | no | yes |

## Light mode: 0-overhead worktrees

On filesystems that support copy-on-write file cloning, worktwin spawns each worker as a CoW clone instead of a full file copy. A 70 GB monorepo with five parallel agents costs around 70 GB total on disk, not 350. Each worker only takes the space its own modifications introduce.

| OS | Filesystem | Supported |
|---|---|---|
| macOS | APFS | yes, default since High Sierra |
| Linux | btrfs | yes |
| Linux | XFS | yes when mounted with `reflink=1` (default on modern kernels) |
| Linux | ZFS | yes with `block_cloning` (OpenZFS 2.2+, kernel 5.3+) |
| Linux | ext4 | no, switch to btrfs or XFS |
| Windows | ReFS Dev Drive | yes, Windows 11 22H2+ |
| Windows | NTFS | no, create a Dev Drive (see below) |

Run `/worktwin-light-doctor` inside Claude Code to find out where your machine sits. On Windows without a Dev Drive, `/worktwin-light-setup-windows` walks you through creating one (admin required, ~100 GB recommended). The Windows Dev Drive path is validated live on Windows 11 25H2 with a 200 GB ReFS volume.

Light mode is automatic. `/worktwin` picks it whenever the filesystem allows, falls back silently to standard worktrees otherwise. If you ever need to override, tell the agent to "force light" or "force heavy" and the skill will pass `--force-light` or `--force-heavy` to `worktwin-init`. The output JSON reports which path was used. Full details in [docs/light-mode.md](docs/light-mode.md).

## Requirements

- git 2.38 or later (uses `git merge-tree --write-tree` for conflict detection)
- Claude Code
- `gh` CLI, optional, for automatic pull requests
- `jq`, optional, for safer state file parsing

## Install

### macOS and Linux

```bash
git clone https://github.com/rhagee/worktwin
cd worktwin
./install.sh           # global, available in every project
./install.sh local     # only this project
```

Remove with `./uninstall.sh` (same mode argument).

### Windows

PowerShell, native:

```powershell
git clone https://github.com/rhagee/worktwin
cd worktwin
.\install.ps1          # global, available in every project
.\install.ps1 local    # only this project
```

Remove with `.\uninstall.ps1` (same mode argument).

If PowerShell blocks the script with `running scripts is disabled on this system`, either run it once with bypass:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Or whitelist your user one time (recommended):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

If you prefer bash, `install.sh` still works from Git Bash or WSL.

---

Once installed, run `/worktwin-help` inside Claude Code at any time for the full list of commands, arguments, and short descriptions. The list is generated from the installed skills, so it always matches what is actually on your machine.

To check if your machine can run light mode, run `/worktwin-light-doctor`. It will detect your filesystem and tell you what to do next.

### Updating

After `git pull` in the cloned repo, re-deploy with `./update.sh` (or `.\update.ps1` on Windows). Both do `git pull --ff-only` and re-run the matching install script.

You can also trigger the same flow from inside Claude Code with `/worktwin-update`. The installer records the path of the cloned repo so the skill knows where to pull from.

## Quick start

Two terminals, same repository:

```
# Terminal 1, Claude Code
/worktwin develop feat/auth "implement Google OAuth login"

# Terminal 2, Claude Code, same repo
/worktwin develop feat/payments "integrate Stripe checkout"
```

Each agent is now bound to its own worktree and branch. The two sessions cannot see or step on each other.

To see who is doing what at any point:

```
/worktwin-status
```

## Shipping

Three ways to wrap up, depending on what you want and what your workflow allows:

```
/worktwin-ship feat/auth                  # ship one specific worker
/worktwin-ship feat/auth feat/payments    # ship a specific subset
/worktwin-ship-all                        # ship every active worker
/worktwin-finalize [<branch> ...]         # local only, no push, no PR
```

`worktwin-ship` and `worktwin-ship-all` push the branches and open or update draft pull requests through `gh`. The agent reads the actual commits and diff and drafts a real PR title and body, matching the conventions it observes in the repo. No fixed template.

`worktwin-ship` requires at least one branch argument on purpose, so a stray invocation never ships eight half-finished branches at once. Use `worktwin-ship-all` when you genuinely want the batch.

`worktwin-finalize` does the same reporting job without the network: it shows what each worker did and prints the exact `git push` and `gh pr create` commands for you to run yourself when ready. Use it when `gh` is not available, when company policy forbids auto-PRs, or when you want to review locally before anything leaves your machine.

## Iterating in the same chat

After `/worktwin`, the session is configured. Keep sending follow-up messages in the same chat: the agent stays on the same branch, commits as it goes, and the next ship call updates the existing PR instead of opening a duplicate.

The rules also survive `/compact` and any new Claude Code session opened in the worktree, because worktwin writes them into the worktree's `CLAUDE.md` in a clearly marked block. Existing `CLAUDE.md` content is preserved.

## A real example

Four parallel features against two different base branches:

```
/worktwin release/1.4 fix/login-crash "fix the crash on submit when the form is empty"
/worktwin develop feat/dark-mode "ship dark mode behind a feature flag"
/worktwin develop feat/csv-export "add CSV export to the reports page"
/worktwin develop chore/upgrade-react "upgrade React to 19.1 and fix any breakage"
```

Four worktrees on disk, four bound sessions, zero interference. When the hotfix is done first, ship it alone:

```
/worktwin-ship fix/login-crash
```

When the other three are also done, batch them out:

```
/worktwin-ship-all
```

## How it works

Short version: `git worktree` for filesystem isolation, a state file in the shared `.git` directory for cross-worktree discovery, and a marked block in the worktree's `CLAUDE.md` so the rules persist across `/compact` and new sessions. The mechanical work runs through scripts in `bin/` so it is deterministic and testable; the skills are thin orchestrators that let the agent handle the judgement parts (drafting PRs, deciding on warnings).

Full breakdown in [docs/how-it-works.md](docs/how-it-works.md). Light mode details and OS-specific setup in [docs/light-mode.md](docs/light-mode.md). Comparison with other tools in [docs/vs-other-tools.md](docs/vs-other-tools.md). The `bin/` script contract in [docs/scripts.md](docs/scripts.md). Common issues in [docs/troubleshooting.md](docs/troubleshooting.md).

## Standalone CLI

The `bin/` scripts work from any shell, not just from inside Claude Code. After install they land in `~/.claude/skills/worktwin/bin/`. Add that to your PATH to call them directly:

```bash
worktwin-init develop feat/auth "implement Google OAuth login"
worktwin-list | jq -c 'select(.commits_ahead > 0)'
worktwin-claude-md /path/to/worktree feat/auth develop "the task"
```

Full contract and usage in [docs/scripts.md](docs/scripts.md).

## Related work

worktwin is not the first CoW worktree tool and not the first AI-agent worktree orchestrator. It is the intersection: a Claude Code skill that uses CoW where the filesystem allows, persists the agent rules through `CLAUDE.md`, coordinates ship and clear, and automates Windows Dev Drive setup for users without one. The four-step pattern in `--light` mode (worktree add `--no-checkout`, CoW-clone, `git checkout` to anchor) is exactly what [josharian/git-cow-worktree](https://github.com/josharian/git-cow-worktree) and the [commaok.xyz design note](https://commaok.xyz/post/git-cow-worktrees/) describe, and we credit them.

Other tools in the space: [joeinnes/cow](https://github.com/joeinnes/cow) (Rust + Swift workspace manager with MCP), [anomalyco/rift](https://github.com/anomalyco/rift) (APFS clonefile), [bkildow/wt-cli](https://github.com/bkildow/wt-cli) (CoW worktree CLI). Anthropic's native [`claude --worktree`](https://code.claude.com/docs/en/worktrees) (Feb 2026) creates worktrees from the Claude Code CLI but does not configure the agent or coordinate the ship lifecycle. A wider 2026 ecosystem of AI-agent worktree orchestrators (Conductor, Vibe Kanban, Claude Squad, Cline, Cursor, Windsurf) is surveyed in [Nimbalyst's comparison](https://nimbalyst.com/blog/best-git-worktree-tools-ai-coding-2026/).

Full credits and links in [docs/related-work.md](docs/related-work.md).

## Contributing

Issues and pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT, see [LICENSE](LICENSE).
