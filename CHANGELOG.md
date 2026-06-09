# Changelog

## v1.0.0 - 2026-06-10

Initial public release.

### Skills

- `/worktwin` binds a Claude Code session to an isolated worktree on a dedicated branch and pins the rules into a marked block of the worktree's `CLAUDE.md` so they survive `/compact` and any new session opened in the directory.
- `/worktwin-status` lists every active worker on the current repo with progress.
- `/worktwin-ship` and `/worktwin-ship-all` push branches and open or update draft pull requests. The agent reads the actual commits and diff and drafts a real PR title and body, matching repo conventions instead of using a fixed template.
- `/worktwin-finalize` does the same reporting work without touching the remote, useful where `gh` is not available or company policy forbids auto-PRs.
- `/worktwin-clear` drops the state record for a stale worker whose worktree was removed.
- `/worktwin-help` lists every installed command, generated from the SKILL.md frontmatter so it stays in sync without manual updates.
- `/worktwin-update` pulls the cloned worktwin repo and re-runs the installer from inside Claude Code.
- `/worktwin-light-doctor` detects whether this machine supports light mode and walks the user through any setup needed.
- `/worktwin-light-setup-windows` automates Windows 11 Dev Drive creation (VHDX + ReFS) for users without a Dev Drive yet.

### Light mode

0-overhead worktrees via filesystem copy-on-write file cloning. On capable filesystems, a new worker starts with near-zero disk overhead and grows only as the agent writes to it.

- macOS APFS: `cp -c` (clonefile) - validated live on Apple Silicon
- Linux btrfs: `cp -a --reflink=auto`
- Linux XFS with reflink: same, with runtime reflink probe
- Linux ZFS with block_cloning: gated by reflink probe
- Windows 11 Dev Drive (ReFS): `Copy-Item` triggers Block Cloning automatically
- Anywhere else: falls back silently to a standard `git worktree add`

Configuration of cross-volume light bases via `bin/worktwin-light-base` so Windows users with the main repo on NTFS and a Dev Drive at `D:\` can still get the storage win.

### Standalone CLI

Every mechanical operation lives in `bin/` and is invokable from a shell, not just from the skills:

- `worktwin-init`
- `worktwin-claude-md`
- `worktwin-list`
- `worktwin-clear`
- `worktwin-light-check`
- `worktwin-light-clone`
- `worktwin-light-base`
- `worktwin-light-setup-windows.ps1`
- `worktwin-help`
- `worktwin-update`

Each script has `-h` / `--help`. Contract documented in `docs/scripts.md`.

### Installers

Both bash (`install.sh`) and PowerShell (`install.ps1`) installers ship. Global install lives at `~/.claude/skills/`, per-project install at `<repo>/.claude/skills/`. `update.sh` and `update.ps1` re-deploy after `git pull`. The installer records the clone path in `~/.claude/skills/worktwin/.source` so `/worktwin-update` always finds the right repo.

### Tests

Bats coverage for the deterministic `bin/` scripts: spawn, state file, idempotent block update, NDJSON discovery, stale clear, light-mode detection JSON shape, light-base CRUD, light-clone semantics, and `--light=on|off|auto` plus invalid flag handling on worktwin-init.

### Known gaps

- Linux btrfs/XFS/ZFS light mode is code-complete but not yet validated against real hardware in v1.0. Community testers welcome. The detection script probes reflink support at runtime, so a misconfigured XFS volume reports clearly instead of silently failing.
- Windows ReFS Block Cloning is code-complete; live validation pending a Dev Drive on the developer's machine.
