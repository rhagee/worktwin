---
name: worktwin-light-teardown-windows
description: Walk the user through undoing a Windows Dev Drive that was set up by /worktwin-light-setup-windows. Unregisters the boot-time auto-mount task, dismounts the VHDX, and (with explicit confirmation) deletes the VHDX file. Also offers a -RegisterAutoMountOnly recovery path for Dev Drives created by older worktwin versions that did not register the task. Requires admin rights.
disable-model-invocation: true
allowed-tools: Bash(test *), Bash(uname *), Bash(powershell *), Read
---

# worktwin-light-teardown-windows

Cleanly remove a worktwin Dev Drive, or repair an older install that is missing the auto-mount task.

The mechanical work happens in `bin/worktwin-light-teardown-windows.ps1`. This skill negotiates the mode and confirmations.

## 1. Confirm we are on Windows

```bash
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    echo "this skill only applies to Windows."
    exit 0
    ;;
esac
```

## 2. Locate the teardown script

```bash
WORKTWIN_BIN=""
for try in "$HOME/.claude/skills/worktwin/bin" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/bin"; do
  if [ -d "$try" ]; then WORKTWIN_BIN="$try"; break; fi
done
[ -z "$WORKTWIN_BIN" ] && { echo "ERROR: worktwin bin/ not found" >&2; exit 1; }
SCRIPT="$WORKTWIN_BIN/worktwin-light-teardown-windows.ps1"
```

## 3. Pick the mode

Ask the user which case applies:

- **Repair** ("my Dev Drive disappears after reboot"): the existing VHDX is fine, the boot-time task is missing. Use `-RegisterAutoMountOnly`. Nothing is deleted. This is the common case for anyone who ran a worktwin version older than the auto-mount fix.
- **Full teardown** ("I am done with this Dev Drive, remove everything"): unregister the task, dismount, then (with confirmation) delete the VHDX file.
- **Keep the file, just free the letter**: unregister + dismount, keep the `.vhdx` on disk. Useful when the user wants to free a drive letter temporarily but plans to come back to the data.

## 4. Resolve the VHDX path

If the user does not pass a path, run the script with no `-VhdPath` so it auto-detects a `worktwin-*.vhdx` on the system. If the script reports more than one candidate, list them and ask the user to pick one.

## 5. Run the script

The script requires admin. If the user's shell is not elevated, tell them to relaunch PowerShell as Administrator and re-invoke this skill.

**Repair (recover an older install):**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" \
  -RegisterAutoMountOnly -VhdPath "$VHD_PATH"
```

This mounts the VHDX if it is not already attached, and registers the auto-mount task that should have been registered the first time. Nothing else is touched.

**Full teardown, interactive:**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" \
  -VhdPath "$VHD_PATH"
```

The script will ask the user at each step (unregister task? dismount? delete file?) so they can opt out per step.

**Full teardown, scripted:**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" \
  -VhdPath "$VHD_PATH" -NonInteractive -DeleteFile
```

Use only when the user has already confirmed they want everything gone.

**Keep the file, just unmount and unregister:**

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT" \
  -VhdPath "$VHD_PATH" -KeepFile
```

## 6. Report what happened

Stream the script output. The script logs every action with `[ok]` for done and `[--]` for skipped. The final line is `teardown complete` or, in repair mode, an instruction to reboot once to verify.

## 7. Do not chain this with setup

This skill is one operation. If the user wants to recreate the Dev Drive after teardown, point them at `/worktwin-light-setup-windows` as a follow-up. Do not auto-trigger it.
