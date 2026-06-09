# Related work

worktwin lives in a small but growing space of tools that combine git worktrees, filesystem copy-on-write, and AI coding agents. The list below is what informed the design and where the prior art is. If you ship a tool in this space and want to be listed (or de-listed), open an issue or PR.

## Copy-on-write git worktrees

These tools focus on the CoW worktree primitive itself. They are not Claude Code specific.

- **[josharian/git-cow-worktree](https://github.com/josharian/git-cow-worktree)** - drop-in CoW replacement for `git worktree add`, written in Go. Picks a source worktree by commit-distance heuristics, uses `git ls-tree -r` to compare blob SHAs and only reflinks files that match exactly. Edge cases (symlinks, submodules, mode mismatches) are left for `git checkout` to fill in. The four-step pattern (worktree add `--no-checkout`, pick source, reflink matching files, `git checkout`) is exactly the shape worktwin uses for its `--light` path; we credit josharian's tool and the blog post below for that shape.

- **[joeinnes/cow](https://github.com/joeinnes/cow)** - Rust + Swift workspace manager. Uses APFS `clonefile(2)` on macOS, `cp --reflink=always` on btrfs/XFS. Adds workspace abstractions ("pastures"), automatic dependency directory handling, post-clone artifact cleanup via `.cow.json`, package-manager detection, and an MCP server mode for agent automation. Heavier surface than worktwin but the same CoW primitive.

- **[anomalyco/rift](https://github.com/anomalyco/rift)** - APFS clonefile-based worktree management. Supports both exact and filtered copies.

- **[bkildow/wt-cli](https://github.com/bkildow/wt-cli)** - git worktree manager CLI with CoW on APFS, btrfs, and XFS reflink mounts. Generic worktree manager rather than agent-targeted.

- **[Copy-on-write git worktrees](https://commaok.xyz/post/git-cow-worktrees/)** by commaok - the design note that crystallised the pattern: `git worktree add --no-checkout`, find a similar worktree, reflink its files, let `git checkout` finalise. Plain and right.

## Native Claude Code support

- **[claude --worktree](https://code.claude.com/docs/en/worktrees)** - Anthropic shipped native worktree support in the Claude Code CLI in February 2026 ([announcement](https://www.threads.com/@boris_cherny/post/DVAAnexgRUj/introducing-built-in-git-worktree-support-for-claude-code-now-agents-can-run-in)). Creates a worktree and opens a session. Does not configure the agent, does not coordinate ship or merge, does not use CoW.

- **`.claude/skills` auto-loading** - Claude Code now auto-loads plugins from `.claude/skills` so a skill folder dropped into `~/.claude/skills` is available without a marketplace round-trip. worktwin's installation model is built on this.

## AI agent + worktree orchestrators

A category that grew quickly in 2026. Most do not do CoW; they wrap standard git worktree.

- **Conductor, Vibe Kanban, Claude Squad, Cline, Cursor, Windsurf** - the survey at [Nimbalyst's 2026 comparison](https://nimbalyst.com/blog/best-git-worktree-tools-ai-coding-2026/) covers them. Each takes a different angle (GUI manager, kanban board, terminal multiplexer, IDE integration).

- Articles and guides framing the pattern: [Augment Code's guide](https://www.augmentcode.com/guides/git-worktrees-parallel-ai-agent-execution), [Parallel Code's overview](https://parallelcode.app/blog/parallel-ai-agents/), [Mindstudio's primer](https://www.mindstudio.ai/blog/what-is-claude-code-git-worktree-pattern-parallel-feature-branches).

## Where worktwin fits

worktwin is not the first CoW worktree tool, and it is not the first AI-agent worktree orchestrator. It is what comes out when you draw a Venn diagram of:

- A Claude Code skill, not a separate CLI - lives in `.claude/skills/`, picks up the conventions of every other skill on the user's machine, ships and updates through the same path
- Filesystem CoW for 0 disk overhead on APFS, btrfs, XFS with reflink, and Windows ReFS
- A marked block in the worktree's `CLAUDE.md` so the agent rules survive `/compact` and any new session opened in the directory (a pattern we have not seen documented in any of the other tools)
- A cross-volume light base for the very common Windows pattern of a large repo on NTFS and a Dev Drive on ReFS at a separate letter
- Automation for Windows Dev Drive creation (`worktwin-light-setup-windows.ps1`) so users on Windows 11 22H2+ can get to light mode without leaving the skill

Each individual piece has prior art. The combination, especially the Windows-ReFS-Dev-Drive-cross-volume path and the CLAUDE.md persistence pattern, is what makes worktwin worth installing if you have one of those gaps to fill. We owe josharian's tool and the commaok blog post for the CoW worktree shape we use, and Anthropic for the underlying `.claude/skills` mechanism that lets worktwin work as a skill rather than a separate process.

## Earlier wave (filesystem CoW history)

For background on the syscalls and the filesystems involved:

- macOS APFS: [Apple's clonefile() documentation](https://developer.apple.com/library/archive/documentation/General/Conceptual/APFS_Guide/) describes the syscall used by `cp -c`.
- Linux: [reflink documentation](https://www.kernel.org/doc/html/latest/filesystems/btrfs.html) for btrfs, and the [`copy_file_range` man page](https://man7.org/linux/man-pages/man2/copy_file_range.2.html) for the kernel API.
- Windows: [ReFS Block Cloning](https://learn.microsoft.com/windows-server/storage/refs/block-cloning) and [Dev Drive overview](https://learn.microsoft.com/windows/dev-drive/) at Microsoft Learn.
