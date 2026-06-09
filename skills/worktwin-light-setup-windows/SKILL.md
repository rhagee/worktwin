---
name: worktwin-light-setup-windows
description: Walk the user through creating a Windows Dev Drive (ReFS volume with Block Cloning) so worktwin can use light mode. Requires Windows 11 22H2+, admin rights, and roughly 100GB of free disk space. Use only after /worktwin-light-doctor recommends creating a new volume.
disable-model-invocation: true
allowed-tools: Bash(test *), Bash(uname *), Bash(powershell *), Read
---

# worktwin-light-setup-windows

Guide the user through Dev Drive creation. The mechanical work happens in `bin/worktwin-light-setup-windows.ps1`; this skill negotiates the parameters and runs the script with explicit consent.

## 1. Confirm we are on Windows

```bash
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    echo "this skill only applies to Windows. On macOS use APFS (already CoW), on Linux use btrfs or XFS."
    exit 0
    ;;
esac
```

## 2. Recap the situation for the user

In plain words, tell the user:

- This will create a virtual disk file (VHDX) at a path they choose, default `C:\worktwin-dev-drive.vhdx`.
- The VHDX is dynamic: it consumes only the space actually used, up to the cap. Default cap is 100 GB.
- The VHDX is mounted as a new drive letter (default `D:`). The new drive is formatted as ReFS with Dev Drive optimisations.
- The operation needs an elevated PowerShell. If they are not already in one, they have to relaunch and rerun.
- Nothing on existing volumes is touched.

## 3. Collect parameters from the user

Ask the user, in order, with defaults shown:

- VHDX path (default: `C:\worktwin-dev-drive.vhdx`)
- Size in GB (default: 100, minimum 50)
- Drive letter (default: D)

If they want defaults for all three, fine. Capture the three values.

## 4. Locate the setup script

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
SCRIPT="$WORKTWIN_BIN/worktwin-light-setup-windows.ps1"
```

## 5. Run a dry run first

Before mutating anything, run the script with `-DryRun` so the user sees exactly what would happen:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" -DryRun \
  -VhdPath "$VHD_PATH" -SizeGB "$SIZE_GB" -DriveLetter "$DRIVE_LETTER" -NonInteractive
```

Show the output to the user verbatim. The dry run does pre-flight checks (Windows version, admin rights, free space, drive letter availability) and stops before any creation.

If pre-flight fails, surface the reason. Common failures:

- Not Windows 11 22H2+ -> Dev Drive is not supported on this OS; user has to upgrade or use the standard worktwin flow.
- Not admin -> tell them to relaunch PowerShell as Administrator and re-invoke this skill.
- Drive letter taken -> ask for a different letter.
- VHDX path exists -> ask for a different path.
- Not enough free space -> ask for a smaller size or a different VHDX location.

## 6. Confirm and run for real

If the dry run is clean, ask the user explicitly:

```
Ready to create the Dev Drive at <VHD_PATH>, size <SIZE_GB>GB, mounted at <DRIVE_LETTER>:?
Type 'yes' to proceed.
```

On 'yes', run the script without `-DryRun`:

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" \
  -VhdPath "$VHD_PATH" -SizeGB "$SIZE_GB" -DriveLetter "$DRIVE_LETTER" -NonInteractive
```

Stream the output. The script logs each step. When it finishes, the new drive is ready.

On anything other than 'yes', stop. No state is changed.

## 7. Confirm with the doctor

Tell the user the next step: re-run `/worktwin-light-doctor <DRIVE_LETTER>:\` to confirm the new drive is CoW-capable and ready for light mode.

If you have time, run it for them and report the result.

## 8. Do not handle removal

This skill creates. It does not remove. If the user wants to undo the Dev Drive, the setup script's output already prints the two commands they need:

```
Dismount-VHD -Path '<VHD_PATH>'
Remove-Item '<VHD_PATH>'
```

Pointing them at those commands is enough. A dedicated removal skill is overkill for v1.0.
