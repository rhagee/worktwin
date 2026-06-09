---
name: worktwin-light-doctor
description: Diagnose whether this machine can run worktwin in light mode (0-overhead worktrees via filesystem copy-on-write) and walk the user through any setup needed. Read-only by default. Use when the user wants to know if they can use light mode, or when they want help enabling it.
argument-hint: '[path]'
arguments: [path]
disable-model-invocation: true
allowed-tools: Bash(bash *), Bash(powershell *), Bash(test *), Bash(jq *), Bash(uname *), Read
---

# worktwin-light-doctor

Detect whether the user's machine can host worktwin's light mode (CoW-based worktrees) at the given path. If yes, confirm. If no, explain why and offer concrete next steps.

The actual probing runs in `bin/worktwin-light-check`. This skill only orchestrates: run the check, parse the JSON, talk to the user.

## 1. Locate the bin directory

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
```

## 2. Detect OS and pick the right checker

```bash
OS=$(uname -s)
TARGET_PATH="${path:-$(pwd)}"

case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    JSON=$(powershell -NoProfile -ExecutionPolicy Bypass -File "$WORKTWIN_BIN/worktwin-light-check.ps1" -Path "$TARGET_PATH")
    ;;
  *)
    JSON=$(bash "$WORKTWIN_BIN/worktwin-light-check" "$TARGET_PATH")
    ;;
esac
```

The PowerShell call is needed on Windows because filesystem detection there needs `Get-Volume`, which is PowerShell-only.

## 3. Parse the JSON

Extract: `os`, `filesystem`, `cow_capable`, `path`, `reason`, `recommendation`, and (Windows only) `dev_drives`. Use `jq` if available.

## 4. Report and recommend

The report is conversational. Lead with the verdict, then explain why, then offer concrete next steps. Use the table below as a guide, but always tailor wording to what the user actually asked.

### When `cow_capable` is `true`

Tell the user: light mode is available on this path. List the filesystem name and any context. Offer to register this path as the light-mode base for their repo when worktwin-init gains light mode support (the marker will live at `~/.claude/skills/worktwin/.light-bases.json`).

For now (v1.0 development phase) just confirm capability and stop. No state changes.

### When `recommendation` is `switch-path` (Windows ReFS exists elsewhere)

Tell the user: their current path is on NTFS but the machine has a Dev Drive (or another ReFS volume) already. List the Dev Drives in the `dev_drives` array. Suggest one of:

- Clone the worktwin repo to the Dev Drive and reinstall, so its bin lives on capable storage.
- Or, more commonly, configure a light-mode base for their large repo: point worktwin at the Dev Drive even though the main checkout stays on the original volume.

Do not run any setup. The user decides. Offer to run `/worktwin-light-doctor <dev_drive_path>` to confirm the Dev Drive is ready.

### When `recommendation` is `create-volume` (Windows, no Dev Drive)

Tell the user: no ReFS volume on this machine. To get light mode they need a Dev Drive. Requirements: Windows 11 22H2 or later, admin rights, ~100GB free space.

Ask explicitly whether they want a step-by-step walkthrough or a fully automated setup. Do not run anything yet. The Dev Drive setup script will land in a separate skill (`worktwin-light-setup-windows`) so the doctor can stay diagnostic-only.

Reference the official Microsoft documentation: https://learn.microsoft.com/windows/dev-drive/

### When `recommendation` is `remount` (Linux XFS without reflink)

Tell the user: their XFS volume was created without reflink support. Two options:

- Remount with `reflink=1` if the kernel supports it on this device. Risky to suggest blindly without knowing their layout.
- Reformat the device with reflinks enabled (destructive, off the table for doctor).

Suggest checking `mount | grep <device>` and consulting their distro's XFS docs.

### When `recommendation` is `filesystem-not-supported` (Linux ext4, macOS HFS+, etc.)

Tell the user: this filesystem does not support reflink. The realistic paths are:

- Use a different mount point that lives on a CoW filesystem (btrfs/XFS on Linux, an external APFS volume on macOS).
- Or work without light mode. Worktwin still runs, the worktrees just use the normal git-checkout-and-copy path with full duplication.

Do not suggest reformatting their home volume.

### When `recommendation` is `unknown` or anything else

Show the raw JSON to the user and ask them to file an issue at https://github.com/rhagee/worktwin with the output so we can extend detection.

## 5. End-of-report hint

Whatever the outcome, end the report with one short line:

```
re-run /worktwin-light-doctor <path> to check a different path.
```

So the user knows they can probe other directories without remembering the command.

## 6. Do not write state

This skill is diagnostic in v1.0. No config writes, no Dev Drive creation, no volume modifications. Setup actions go through dedicated skills (`worktwin-light-setup-windows`, `worktwin-light-base`) which require explicit invocation.
