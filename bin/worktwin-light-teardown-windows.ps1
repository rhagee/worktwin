#Requires -Version 5.1
<#
worktwin-light-teardown-windows.ps1 - undo a Dev Drive set up by
worktwin-light-setup-windows.ps1.

Three operations, all reversible up to the point indicated:

  1. Unregister the auto-mount scheduled task for this VHDX (so it
     stops trying to mount it at boot). Reversible: re-run setup.
  2. Dismount the VHDX if it is currently mounted. Reversible: just
     re-mount.
  3. Delete the VHDX file from disk. NOT reversible without a backup.

By default the script does (1) and (2), then asks before doing (3).
Pass -KeepFile to skip step 3 unconditionally (useful when you want
to free the drive letter temporarily but keep the data).

Usage:
  .\worktwin-light-teardown-windows.ps1
      Interactive: detect a single worktwin VHDX, confirm each step.

  .\worktwin-light-teardown-windows.ps1 -VhdPath D:\worktwin-dev-drive.vhdx
      Target a specific VHDX path.

  .\worktwin-light-teardown-windows.ps1 -VhdPath ... -KeepFile
      Unregister + dismount but keep the .vhdx on disk.

  .\worktwin-light-teardown-windows.ps1 -VhdPath ... -NonInteractive -DeleteFile
      Full cleanup without prompts (CI / scripted use).

  .\worktwin-light-teardown-windows.ps1 -RegisterAutoMountOnly -VhdPath ...
      Special case: register the auto-mount task for an existing,
      working VHDX without touching anything else. Useful when the
      Dev Drive was created by an earlier worktwin version that did
      not register the task, leaving a working VHDX file without the
      boot-time mount entry.
#>

[CmdletBinding()]
param(
    [string]$VhdPath,
    [switch]$KeepFile,
    [switch]$DeleteFile,
    [switch]$NonInteractive,
    [switch]$RegisterAutoMountOnly,
    [switch]$NoElevate
)

function Fail($msg) {
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}
function Step($msg) { Write-Host ">> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "   $msg" -ForegroundColor Gray }
function Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }
function Skip($msg) { Write-Host "[--] $msg" -ForegroundColor DarkGray }

function Confirm-Or-Skip($prompt) {
    if ($NonInteractive) { return $false }
    $ans = Read-Host "$prompt (type 'yes' to proceed, anything else to skip)"
    return ($ans -eq 'yes')
}

function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Auto-elevation: same UAC trick as worktwin-light-setup-windows.ps1.
# Run from any plain PowerShell, click Yes on the prompt, and the
# elevated child does the work in a new window. -NoElevate prevents
# recursion; -NonInteractive disables the prompt (CI use only).
if (-not (Test-IsAdmin) -and -not $NoElevate) {
    if ($NonInteractive) {
        Fail "this script needs admin rights and -NonInteractive disables UAC self-elevation. Run from an elevated PowerShell, or omit -NonInteractive to trigger the UAC prompt."
    }
    Write-Host ">> Not running as admin. Asking Windows to elevate (UAC prompt incoming)..." -ForegroundColor Cyan
    Write-Host "   Click 'Yes' on the Windows prompt. The teardown will run in a new admin window." -ForegroundColor Gray

    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File', "`"$($MyInvocation.MyCommand.Path)`"", '-NoElevate')
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) {
            if ($v.IsPresent) { $argList += "-$k" }
        } else {
            $argList += "-$k"
            $argList += "`"$v`""
        }
    }

    try {
        $proc = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -Wait -PassThru -ErrorAction Stop
        Write-Host ">> Elevated teardown finished (exit code $($proc.ExitCode))." -ForegroundColor Cyan
        exit $proc.ExitCode
    } catch {
        Fail "UAC elevation was denied or failed. Re-run and accept the prompt, or launch PowerShell as Administrator manually."
    }
}

# Sanity check (we should be admin now)
Step "Pre-flight: admin rights"
if (-not (Test-IsAdmin)) {
    Fail "still not running with admin rights after elevation attempt. Aborting."
}
Ok "running with admin rights"

# Resolve VhdPath: explicit, or detect a single worktwin VHDX on the
# system (anything with file name worktwin-*.vhdx).
if (-not $VhdPath) {
    Step "Detecting worktwin VHDX files"
    $candidates = @()
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem).Root) {
        $hits = Get-ChildItem -Path $drive -Filter 'worktwin-*.vhdx' -ErrorAction SilentlyContinue -Depth 3 2>$null
        if ($hits) { $candidates += $hits }
    }
    if ($candidates.Count -eq 0) {
        Fail "no worktwin-*.vhdx file found. Pass -VhdPath explicitly."
    }
    if ($candidates.Count -gt 1) {
        Info "found multiple candidate VHDX files:"
        foreach ($c in $candidates) { Info "  $($c.FullName)" }
        Fail "more than one candidate. Re-run with -VhdPath <one of the above>."
    }
    $VhdPath = $candidates[0].FullName
    Ok "auto-detected $VhdPath"
} else {
    if (-not (Test-Path -LiteralPath $VhdPath)) {
        # Still allow teardown of stale task/registration even if file missing.
        Info "VHDX file not present at $VhdPath (continuing with task/mount cleanup)"
    } else {
        $VhdPath = (Resolve-Path -LiteralPath $VhdPath).Path
    }
}

$taskName = "worktwin-mount-" + [IO.Path]::GetFileNameWithoutExtension($VhdPath)

# --- Special case: register-only mode --------------------------------------
if ($RegisterAutoMountOnly) {
    if (-not (Test-Path -LiteralPath $VhdPath)) {
        Fail "cannot register auto-mount for a missing VHDX: $VhdPath"
    }

    # Locate the mount helper script. It lives in the same bin dir as
    # this script when installed via install.ps1 / install.sh. We avoid
    # Mount-VHD / Get-VHD direct calls here on purpose - they are
    # missing on Windows Home and break this entire flow if assumed.
    $helperScript = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'worktwin-mount-helper.ps1'
    if (-not (Test-Path -LiteralPath $helperScript)) {
        Fail "mount helper script not found at $helperScript. Re-run the install."
    }

    Step "Mounting $VhdPath via helper (if not already attached)"
    & $helperScript -VhdPath $VhdPath
    $alreadyMounted = $false
    try {
        $alreadyMounted = [bool](Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'File Backed Virtual' -and $_.OperationalStatus -eq 'Online' })
    } catch { }
    if ($alreadyMounted) { Ok "VHDX is attached" } else { Info "VHDX mount status uncertain (no FBV disk visible)" }

    Step "Registering auto-mount task '$taskName'"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helperScript`" -VhdPath `"$VhdPath`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
        -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    try {
        Register-ScheduledTask -TaskName $taskName `
            -Description "Re-mount the worktwin Dev Drive VHDX at $VhdPath at every system startup, via $helperScript. Created by worktwin-light-teardown-windows.ps1 -RegisterAutoMountOnly." `
            -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
        Ok "scheduled task '$taskName' registered"
    } catch {
        Fail "Register-ScheduledTask failed: $($_.Exception.Message)"
    }

    $vol = Get-Disk | Where-Object { $_.BusType -eq 'File Backed Virtual' } | Get-Partition |
           Where-Object { $_.DriveLetter } | Select-Object -First 1
    if ($vol) {
        Ok "Dev Drive available at $($vol.DriveLetter):"
    }
    Write-Host ""
    Write-Host "Reboot once to verify the task brings the Dev Drive back automatically." -ForegroundColor Green
    if ($NoElevate -and -not $NonInteractive) {
        Write-Host ""
        Read-Host "Press Enter to close this window"
    }
    exit 0
}

# --- Normal teardown flow --------------------------------------------------

# Step 1: unregister the scheduled task
Step "Looking for scheduled task '$taskName'"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    if ($NonInteractive -or (Confirm-Or-Skip "Unregister scheduled task '$taskName'?")) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Ok "task unregistered"
    } else {
        Skip "kept (user)"
    }
} else {
    Skip "no such task"
}

# Step 2: dismount the VHDX. Hyper-V-agnostic: use Mount/Dismount-VHD
# when available, fall back to diskpart on Windows Home.
function Dismount-VhdAgnostic([string]$Path) {
    if (Get-Command Dismount-VHD -ErrorAction SilentlyContinue) {
        Dismount-VHD -Path $Path -ErrorAction Stop
        return
    }
    $script = @"
select vdisk file="$Path"
detach vdisk
"@
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmp -Value $script -Encoding ascii
        $out = & diskpart /s $tmp 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "diskpart detach failed: $out"
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

Step "Checking if $VhdPath is mounted"
$attached = $false
if (Test-Path -LiteralPath $VhdPath) {
    if (Get-Command Get-VHD -ErrorAction SilentlyContinue) {
        try { $attached = (Get-VHD -Path $VhdPath -ErrorAction Stop).Attached } catch { $attached = $false }
    } else {
        # No Get-VHD: best-effort heuristic. If any File Backed Virtual
        # disk is online and this is the only worktwin VHDX on the box,
        # assume it is ours. Worst case: detach is a no-op or errors,
        # which is handled.
        try {
            $fbv = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'File Backed Virtual' -and $_.OperationalStatus -eq 'Online' }
            if ($fbv) { $attached = $true }
        } catch { }
    }
}
if ($attached) {
    if ($NonInteractive -or (Confirm-Or-Skip "Dismount VHDX?")) {
        try {
            Dismount-VhdAgnostic $VhdPath
            Ok "dismounted"
        } catch {
            Info "dismount failed: $($_.Exception.Message)"
        }
    } else {
        Skip "kept mounted (user)"
    }
} elseif (Test-Path -LiteralPath $VhdPath) {
    Skip "not currently mounted"
} else {
    Skip "VHDX file does not exist; nothing to dismount"
}

# Step 3: delete the VHDX file
if (Test-Path -LiteralPath $VhdPath) {
    if ($KeepFile) {
        Skip "kept VHDX file at $VhdPath (-KeepFile)"
    } else {
        Step "Delete VHDX file $VhdPath"
        $size = [Math]::Round((Get-Item -LiteralPath $VhdPath).Length / 1GB, 2)
        Info "current file size on disk: $size GB"
        $confirmed = $false
        if ($DeleteFile -or $NonInteractive) {
            $confirmed = $true
        } else {
            $confirmed = Confirm-Or-Skip "DELETE this file? It cannot be recovered."
        }
        if ($confirmed) {
            Remove-Item -LiteralPath $VhdPath -Force
            Ok "deleted"
        } else {
            Skip "kept VHDX file (user)"
        }
    }
} else {
    Skip "no VHDX file to delete"
}

Write-Host ""
Ok "teardown complete"

# If we are the elevated child, pause so the user can read.
if ($NoElevate -and -not $NonInteractive) {
    Write-Host ""
    Read-Host "Press Enter to close this window"
}
