# Light mode

Standard `git worktree` creates a fresh working copy on disk every time a new worktree is added. For small repos the cost is invisible. For a 70 GB monorepo with five parallel agents you are looking at 350 GB of duplicated files on top of the main checkout.

Light mode replaces the copy step with a filesystem-level copy-on-write clone. On the filesystems that support it, a new worktree starts at near-zero disk overhead and grows only as the agent writes to it. A 70 GB monorepo with five parallel agents costs about 70 GB plus the divergence each worker introduces.

## Storage comparison

| | Standard worktree | Light mode |
|---|---|---|
| Initial cost per worktree | full working tree (~70 GB for the example) | a few KB (only the index and metadata) |
| Growth | none, files are static copies | proportional to files actually modified |
| Creation time | minutes for very large repos | seconds, regardless of repo size |
| Filesystem requirement | any | APFS, btrfs, XFS with reflink, ReFS |

## Filesystem support

| OS | Filesystem | Light mode | How |
|---|---|---|---|
| macOS | APFS | yes | `cp -c` (clonefile syscall), automatic |
| macOS | HFS+ | no | use APFS, default since High Sierra |
| Linux | btrfs | yes | `cp -a --reflink=auto`, automatic |
| Linux | XFS | yes if `reflink=1` | mount option, default on modern kernels |
| Linux | ZFS | yes if `block_cloning` | requires kernel 5.3+ and OpenZFS 2.2+ |
| Linux | ext4 | no | requires switching to btrfs or XFS |
| Windows | ReFS Dev Drive | yes | `Copy-Item` triggers Block Cloning |
| Windows | NTFS | no | create a Dev Drive (see below) |

Run `/worktwin-light-doctor` inside Claude Code to find out where your machine sits.

## How it works

`worktwin-init` decides at runtime whether to use the light path. The decision tree:

1. If `--light=off`, always standard.
2. If a light base is configured for this main repo (via `worktwin-light-base set ...`) and the base directory is CoW-capable, use cross-volume light mode: the base acts as the source for the clone, the new worktree lives next to it on the same volume.
3. Otherwise, if the main checkout itself sits on a CoW-capable filesystem and is currently on the source branch, use same-volume light mode: clone directly from the main checkout.
4. Otherwise, fall back to a standard `git worktree add`. The output JSON's `light_mode` field reports `off` with a `light_reason` so you can tell why.

The fast path:

```
git worktree add --no-checkout -b <new> <target> <from-ref>
worktwin-light-clone <source> <target>     # CoW copy, skips .git
git -C <target> read-tree --reset HEAD     # align index, no file rewrite
```

The fast path is identical to a standard worktree from git's point of view; it just got its files via CoW instead of through the checkout pipeline.

## Cross-volume light mode (the Windows pattern)

On Windows, most users keep their large repos on `C:` (NTFS, no CoW). Dev Drive is a separate ReFS volume Microsoft introduced for dev workloads in Windows 11 22H2. Light mode handles this with a two-volume layout:

```
C:\dev\bigrepo                  main checkout, NTFS, 70 GB
D:\worktwin-bases\bigrepo       light base, ReFS, registered as a git worktree of C:\dev\bigrepo
D:\worktwin-bases\bigrepo--*    light worktrees, ReFS, Block Cloned from the base
```

Setup:

1. `/worktwin-light-doctor` confirms ReFS is available on `D:`.
2. `git -C C:\dev\bigrepo worktree add D:\worktwin-bases\bigrepo develop` (or whatever branch the worker forks from).
3. `bin/worktwin-light-base set C:\dev\bigrepo D:\worktwin-bases\bigrepo`.
4. Next `/worktwin develop feat/x "task"` lands on `D:\worktwin-bases\bigrepo--feat-x`, Block Cloned from the base. ~70 GB total instead of 140+ GB.

When you spawn from a different base branch, worktwin-init syncs the light base to that branch before forking.

## Setup per OS

### macOS

APFS is the default since High Sierra. Nothing to install. Run `/worktwin-light-doctor` to confirm, then `/worktwin` as usual.

### Linux on btrfs or XFS with reflink

Use the path that lives on the CoW-capable mount. Run `/worktwin-light-doctor /path/to/repo` to confirm. Many modern distros default to btrfs (Fedora) or XFS with reflinks enabled (RHEL 8+, recent Ubuntu).

### Linux on ext4

Two realistic options without reformatting:

1. Use a btrfs or XFS partition you mount somewhere (often `/home` is its own partition; if so and it is btrfs/XFS, point worktwin there).
2. Skip light mode. Worktwin still works, the worktrees just consume normal disk space.

A future release may help create a btrfs loopback file inside an ext4 home so light mode is possible without reformatting. Out of scope for v1.0.

### Windows 11 22H2 or later

Run `/worktwin-light-doctor`. If no Dev Drive exists, run `/worktwin-light-setup-windows` to be walked through creating one. The setup script creates a VHDX, formats it as ReFS, assigns a drive letter, and requires admin rights. It pre-flights everything before mutating anything.

### Windows pre-22H2

Dev Drive is not available. Light mode is not available. Worktwin still works in standard mode.

## CLI cheat sheet

```
worktwin-light-check [path]              detect, print JSON
worktwin-light-base list                 every configured main->base mapping
worktwin-light-base get <main>           one mapping
worktwin-light-base set <main> <base>    add or update a mapping
worktwin-light-base remove <main>        drop a mapping
worktwin-light-clone <src> <dst>         CoW copy, skips .git
```

`worktwin-init` accepts a light-mode flag. The defaults are sensible, but the flag is there when you want to be explicit:

- (no flag, default): try light, fall back to heavy silently. Same as `--light=auto`.
- `--force-light` (alias: `--light`, `--light=on`): require light, exit non-zero if the filesystem does not support it.
- `--force-heavy` (alias: `--no-light`, `--light=off`): always use standard `git worktree add`, never attempt CoW.

Inside Claude Code, ask the agent to "force light" or "force heavy" and the `/worktwin` skill will pass the matching flag. Without an explicit instruction it always uses the default (light when possible).

## Platform status

| Platform | Code complete | Live-tested | Notes |
|---|---|---|---|
| macOS APFS | yes | yes (v1.0) | clonefile via `cp -c`, validated on Apple Silicon |
| Linux btrfs | yes | no (v1.0) | code path mirrors macOS, `cp -a --reflink=auto`. Community validation welcomed |
| Linux XFS reflink | yes | no (v1.0) | same code as btrfs, plus the runtime reflink probe in `worktwin-light-check` |
| Linux ZFS | yes | no (v1.0) | gated by `cp --reflink=always` probe |
| Windows ReFS | yes | no (v1.0) | `Copy-Item` triggers Block Cloning on ReFS-to-ReFS within the same volume |
| Windows NTFS | n/a | yes (v1.0) | correctly falls back to standard `git worktree add` |

If you run light mode on a platform marked "no" for live-tested and find it works (or breaks), please open an issue with the `worktwin-light-check` output and your filesystem details. The code is logically identical across the CoW backends so confidence is high, but live confirmation per platform is the path to a labelled "yes".

## Limitations and caveats

- The light path requires the clone source (main repo or configured base) to be on the same volume as the new worktree, because CoW does not cross volumes on any current filesystem.
- Same-volume light mode requires the main checkout to be on the source branch. If you typically keep main on a long-lived feature branch and spawn from `develop`, configure a light base instead.
- The state file at `.git/parallel/<slug>.json` records whether each worker is light or standard. Reading the file from outside worktwin is straightforward: it is JSON.
- `worktwin-light-base` writes to `~/.claude/skills/worktwin/.light-bases.json`. The file is machine-local and never committed.
