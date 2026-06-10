# Changelog

## Unreleased

### Fixed

- **Verification UX**: `worktwin-light-setup-windows.ps1`'s post-install "next steps" now suggests `schtasks /query /TN <name>` (not `Get-ScheduledTask`) to verify the auto-mount task from a non-admin shell. `Get-ScheduledTask` cannot see SYSTEM-principal tasks from a non-admin caller and returns `$null` silently, which looks like a false negative. New troubleshooting entry documents the gotcha.
- **Critical UX**: `worktwin-light-setup-windows.ps1` and `worktwin-light-teardown-windows.ps1` now self-elevate via UAC. The user no longer has to manually open PowerShell as Administrator before running them. Both scripts detect non-admin, trigger the Windows UAC prompt, and run in a new admin window that pauses at the end so the log is readable. Pass `-NoElevate` to opt out (the elevated child uses this internally to prevent recursion); pass `-NonInteractive` for CI use, which disables UAC self-elevation and requires the caller to already be admin.
- **Critical**: `worktwin-light-setup-windows` now registers a `worktwin-mount-<vhdname>` scheduled task that runs at system startup and re-mounts the Dev Drive VHDX. Without this fix the VHDX file stayed on disk after a reboot but no longer attached to a drive letter, silently breaking light mode until the user noticed the missing letter and reattached manually. Existing installs created by older versions can be repaired non-destructively with `/worktwin-light-teardown-windows -RegisterAutoMountOnly -VhdPath <existing.vhdx>`. Pass `-SkipAutoMountTask` to the setup script to opt out of the new behaviour.

### Added

- **Auto-discovery of the Dev Drive at spawn time.** `worktwin-init` now detects when the main repo lives on a non-CoW filesystem (Windows NTFS being the common case) and a Dev Drive is available on the system. On the first `/worktwin` spawn for that repo it auto-creates an implicit base at `<dev-drive>:\.worktwin-bases\<repo-name>` (a clone of the main repo) and points the worktree at the Dev Drive with cross-volume CoW reflinks. From the second spawn onward the base is reused silently. **No manual setup**: the user keeps their main checkout wherever they want, runs `/worktwin`, and worktwin parks the worker on the fast volume with zero-overhead reflinks. The previously-required `worktwin-light-base set` step is now optional - it stays available for power users who want a custom mapping, but the typical path is fully automatic.
- **Guided Dev Drive setup at install time on Windows.** `install.ps1` now detects when no ReFS volume exists, asks the user whether to set up a Dev Drive immediately, and walks through the three choices (source disk from a list of candidates with at least 50 GB free, drive letter with a smart default, VHDX size cap with a smart default). On accept, it invokes the setup script which self-elevates via UAC. Skip with `-SkipDevDriveSetup` or by answering "no". Non-interactive shells (CI, piped) get a one-line pointer instead of the prompt.
- `/worktwin-light-teardown-windows` and `bin/worktwin-light-teardown-windows.ps1` — clean removal flow for a worktwin Dev Drive. Three modes: full teardown (unregister task → dismount → delete VHDX), keep-the-file (`-KeepFile`), and repair (`-RegisterAutoMountOnly`) for older installs missing the boot-time mount task. Each destructive step prompts unless `-NonInteractive -DeleteFile` is passed.
- `/worktwin-merge-solver <branch> [<branch> ...]` — cross-PR conflict resolution for sibling worktwin workers. Discovers the workers passed as arguments, groups them by `from_branch`, runs `git merge-tree` pairwise per group to find real conflicts, then for each conflicting group reads each worker's `WORKTWIN.md` task, recent commits, and per-file diff to propose an intent-aware resolution. The user can accept the proposal verbatim, override per file ("prefer A on X", "keep both on Y"), pick a custom combined branch name, or skip the group. Conflicting groups collapse into a single combined branch + PR (title and body synthesised from both children's tasks); clean siblings keep their independent PRs. Original PRs are closed as "superseded by #N" only on explicit user confirmation, and the local branches and history are preserved. No force-push, ever.
- New `bin/worktwin-merge-solver` (bash + `.ps1`) with subcommands `discover`, `prepare`, `merge-step`, `finalize-step`, `push`, `open-pr`, `close-original`. Each subcommand is one atomic deterministic operation; the skill orchestrates them and lets the agent drive the conversation.

### Changed

- `worktwin-ship` and `worktwin-ship-all` no longer remove worktrees or state files after a successful ship. Shipping is no longer the worker's terminal event; the worktree, the state file, and the `WORKTWIN.md` context are deliberately preserved so the worker can be reused by `/worktwin-merge-solver` or by the user to iterate further on the branch. Cleanup now happens only via the explicit `/worktwin-clear <branch>`.
- `worktwin-claude-md` now splits the rules across two files instead of cramming everything into the worktree's `CLAUDE.md`. The full DO/DO NOT rules, bound branch, source branch, and task live in a new `WORKTWIN.md` at the worktree root. `CLAUDE.md` keeps any branch-level content (company rules, project standards) verbatim, and gets a small `@WORKTWIN.md` reference block appended at the bottom. The worktwin rules therefore layer on top of the original project rules instead of pushing them down. Existing worktwin blocks are stripped wherever they were and reapplied at the bottom on the next run, so any pre-v1.0.0-style block is migrated automatically.

### Added

- `worktwin-claude-md` now hard-rules both `CLAUDE.md` and `WORKTWIN.md` out of git. Tracked files (e.g., a company `CLAUDE.md` inherited from the branch) get `git update-index --skip-worktree`; untracked files get an anchored entry in the per-worktree `info/exclude`. Both files are also explicitly called out in the appended block, so the agent itself warns the user before any explicit commit. The branch-level `CLAUDE.md` is therefore preserved as content (visible to Claude Code) and as a tracked git object (untouched on the branch).

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
- Windows 11 Dev Drive (ReFS): `Copy-Item` triggers Block Cloning automatically - validated live on Windows 11 25H2
- Windows NTFS: graceful fallback to standard `git worktree add` - validated live
- Linux btrfs: `cp -a --reflink=auto`
- Linux XFS with reflink: same, with runtime reflink probe
- Linux ZFS with block_cloning: gated by reflink probe
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
