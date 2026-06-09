# worktwin

> Spawn isolated Claude Code agents on parallel branches. No conflicts, no chaos.

worktwin is a Claude Code skill, not a CLI tool. Install it once, invoke it inside Claude Code with `/worktwin`, and the agent configures itself to work on a dedicated branch in an isolated git worktree. Multiple sessions on the same repo, zero context bleed.

<!-- TODO: replace with demo GIF -->
![demo](docs/demo.gif)

## The problem

Two Claude Code sessions, same repo, same file: chaos. Plain git worktrees give you filesystem isolation but do not tell the agent how to behave. The agent still wanders, switches branches, edits files in the other worktree, and your parallel work collapses into one tangled history.

## What worktwin does differently

| | `claude --worktree` | `gtr` (CodeRabbit) | worktwin |
|---|---|---|---|
| Creates a worktree | yes | yes | yes |
| Instructs the agent | no | no | yes |
| Tracks active workers | no | no | yes |
| Real conflict detection (not just file overlap) | no | no | yes |
| Pushes branches and opens or updates PRs | no | no | yes |
| Iterates in the same chat | no | no | yes |

## Requirements

- git 2.38 or later (uses `git merge-tree --write-tree` for conflict detection)
- Claude Code
- `gh` CLI, optional, for automatic pull requests
- `jq`, optional, for safer state file parsing
- Windows: run `install.sh` from Git Bash or WSL

## Install

```bash
git clone https://github.com/rhagee/worktwin
cd worktwin
./install.sh           # global, available in every project
./install.sh local     # only this project
```

To remove: `./uninstall.sh` with the same mode.

## Quick start

Two terminals, same repository:

```
# Terminal 1, Claude Code
/worktwin feat/auth develop "implement Google OAuth login"

# Terminal 2, Claude Code, same repo
/worktwin feat/payments develop "integrate Stripe checkout"
```

Each agent is now bound to its own worktree and branch. The two sessions cannot see or step on each other.

When you are done in any session:

```
/worktwin-ship
```

This collects every active worker, pushes the branches, and opens two draft pull requests against `develop`. Existing PRs are updated, not duplicated.

For a quick read-only overview:

```
/worktwin-status
```

## Iterating in the same chat

After `/worktwin`, the session is configured. Keep sending follow-up messages in the same chat: the agent stays on the same branch, commits as it goes, and the next `/worktwin-ship` updates the existing PR instead of opening a new one.

The rules also survive `/compact` and any new Claude Code session opened in the worktree, because worktwin writes them into the worktree's `CLAUDE.md` in a clearly marked block. Existing `CLAUDE.md` content is preserved.

## A real example

Four parallel features against two different base branches:

```
/worktwin fix/login-crash release/1.4 "fix the crash on submit when the form is empty"
/worktwin feat/dark-mode develop "ship dark mode behind a feature flag"
/worktwin feat/csv-export develop "add CSV export to the reports page"
/worktwin chore/upgrade-react develop "upgrade React to 19.1 and fix any breakage"
```

Four worktrees on disk, four bound sessions, zero interference. `/worktwin-ship` at the end opens four draft PRs (or updates them if they already exist).

## How it works

Short version: `git worktree` for filesystem isolation, a state file in the shared `.git` directory for cross-worktree discovery, and a marked block in the worktree's `CLAUDE.md` so the rules persist across `/compact` and new sessions.

Full breakdown in [docs/how-it-works.md](docs/how-it-works.md). Comparison with other tools in [docs/vs-other-tools.md](docs/vs-other-tools.md). Common issues in [docs/troubleshooting.md](docs/troubleshooting.md).

## Contributing

Issues and pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT, see [LICENSE](LICENSE).
