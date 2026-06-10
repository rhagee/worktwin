#Requires -Version 5.1
<#
worktwin-light-setup-windows.ps1 - create a Windows Dev Drive (ReFS
volume with Block Cloning) for use by worktwin light mode. Requires
Windows 11 22H2 or later, admin rights, and enough free disk space.

Usage:
  .\worktwin-light-setup-windows.ps1 -DryRun
      Show what would happen, change nothing.

  .\worktwin-light-setup-windows.ps1 -VhdPath C:\worktwin-dev-drive.vhdx -SizeGB 100 -DriveLetter D
      Create a 100GB VHDX, mount it, format as ReFS Dev Drive, assign D:.

  .\worktwin-light-setup-windows.ps1
      Interactive: ask for VhdPath, SizeGB, DriveLetter, confirm, run.

By default the script is conservative: every mutating step prints
exactly what it is about to do and requires the operator to type 'yes'
to proceed. Pre-flight checks run before anything is created.

Safety notes:
  - Creates a VHDX file at -VhdPath. The file consumes -SizeGB of disk
    space (dynamic, so it grows as data is written, up to the cap).
  - Mounts the VHDX, partitions it, formats it as ReFS with Dev Drive
    optimisations enabled.
  - Registers a scheduled task that re-mounts the VHDX at every system
    startup, so the Dev Drive survives reboots. Task name is derived
    from the VHDX file name (one task per Dev Drive). Pass
    -SkipAutoMountTask to opt out.
  - Does not touch any existing volume.
  - To remove the Dev Drive later: run worktwin-light-teardown-windows
    (or detach the VHD, unregister the task, delete the VHDX file).
#>

[CmdletBinding()]
param(
    [string]$VhdPath,
    [int]$SizeGB,
    [string]$DriveLetter,
    [switch]$DryRun,
    [switch]$NonInteractive,
    [switch]$SkipAutoMountTask,
    [switch]$NoElevate
)

function Fail($msg) {
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}

function Step($msg) { Write-Host ">> $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "   $msg" -ForegroundColor Gray }
function Ok($msg)   { Write-Host "[ok] $msg" -ForegroundColor Green }

function Confirm-Or-Exit($prompt) {
    if ($NonInteractive) { return }
    $ans = Read-Host "$prompt (type 'yes' to proceed)"
    if ($ans -ne "yes") {
        Write-Host "aborted by user" -ForegroundColor Yellow
        exit 0
    }
}

# Auto-elevation: a Dev Drive needs admin to create. Triggering UAC from
# inside the script means the user can launch it from any plain
# PowerShell - no "right-click, Run as Administrator" gymnastics. The
# elevated child runs the same script with -NoElevate, so we do not
# loop. Pause at the end (handled below) so the auto-spawned window
# stays open long enough to read the log.
function Test-IsAdmin {
    return ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdmin) -and -not $NoElevate) {
    if ($NonInteractive) {
        Fail "this script needs admin rights and -NonInteractive disables UAC self-elevation. Run from an elevated PowerShell, or omit -NonInteractive to trigger the UAC prompt."
    }
    Write-Host ">> Not running as admin. Asking Windows to elevate (UAC prompt incoming)..." -ForegroundColor Cyan
    Write-Host "   Click 'Yes' on the Windows prompt. The setup will run in a new admin window." -ForegroundColor Gray

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
        Write-Host ">> Elevated setup finished (exit code $($proc.ExitCode))." -ForegroundColor Cyan
        exit $proc.ExitCode
    } catch {
        Fail "UAC elevation was denied or failed. Re-run and accept the prompt, or launch PowerShell as Administrator manually."
    }
}

# Pre-flight: OS version
Step "Pre-flight: Windows version"
$build = [System.Environment]::OSVersion.Version.Build
Info "OS build: $build (Dev Drive requires 22621 or later, i.e. Windows 11 22H2)"
if ($build -lt 22621) {
    Fail "Dev Drive requires Windows 11 22H2 or later (build 22621+). This system is build $build."
}
Ok "Windows version is sufficient"

# Pre-flight: admin (sanity check - we should be admin by now)
Step "Pre-flight: admin rights"
if (-not (Test-IsAdmin)) {
    Fail "still not running with admin rights after elevation attempt. Aborting."
}
Ok "running with admin rights"

# Pre-flight: existing Dev Drives
Step "Pre-flight: existing Dev Drives"
$existing = Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystem -eq "ReFS" -and $_.DriveLetter }
if ($existing) {
    Info "the machine already has ReFS volumes:"
    foreach ($v in $existing) {
        Info "  $($v.DriveLetter):  size=$([Math]::Round($v.Size/1GB,1))GB  label='$($v.FileSystemLabel)'"
    }
    Info "You can use one of these directly without creating a new Dev Drive."
    if (-not $NonInteractive) {
        $ans = Read-Host "Continue and create another Dev Drive? (yes/no)"
        if ($ans -ne "yes") {
            Write-Host "aborted by user" -ForegroundColor Yellow
            exit 0
        }
    }
}

# Resolve parameters interactively if missing
if (-not $VhdPath) {
    if ($NonInteractive) { Fail "-VhdPath is required in non-interactive mode" }
    $default = "C:\worktwin-dev-drive.vhdx"
    $entered = Read-Host "VHDX path (default: $default)"
    if (-not $entered) { $entered = $default }
    $VhdPath = $entered
}
if (-not $SizeGB) {
    if ($NonInteractive) { Fail "-SizeGB is required in non-interactive mode" }
    $entered = Read-Host "Size in GB (default: 100, min 50 for ReFS Dev Drive)"
    if (-not $entered) { $entered = 100 }
    $SizeGB = [int]$entered
}
if ($SizeGB -lt 50) {
    Fail "Dev Drive requires at least 50 GB. Requested: $SizeGB"
}
if (-not $DriveLetter) {
    if ($NonInteractive) { Fail "-DriveLetter is required in non-interactive mode" }
    $entered = Read-Host "Drive letter to assign (default: D)"
    if (-not $entered) { $entered = "D" }
    $DriveLetter = $entered.TrimEnd(':').ToUpper()
}

# Validate drive letter availability
Step "Pre-flight: drive letter '$DriveLetter' free"
if (Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue) {
    Fail "drive letter $DriveLetter`: is already in use. Choose another."
}
Ok "drive letter $DriveLetter`: is available"

# Validate VHDX path
Step "Pre-flight: VHDX path '$VhdPath' free"
if (Test-Path $VhdPath) {
    Fail "$VhdPath already exists. Move it aside or pick a different path."
}
$parent = Split-Path -Parent $VhdPath
if (-not (Test-Path $parent)) {
    Fail "parent directory does not exist: $parent"
}
Ok "VHDX path is free"

# Validate free space (rough: VHDX max size)
Step "Pre-flight: free disk space on $($parent.Substring(0,2))"
$drive = $parent.Substring(0,1)
$freeGB = [Math]::Round((Get-PSDrive -Name $drive).Free / 1GB, 1)
if ($freeGB -lt $SizeGB) {
    Fail "not enough free space on $drive`:. Need $SizeGB GB, have $freeGB GB."
}
Info "free on $drive`:: $freeGB GB, requested: $SizeGB GB (dynamic VHDX, grows on use)"
Ok "free space is sufficient"

# Pick implementation path: Hyper-V cmdlets if available, diskpart otherwise
Step "Pre-flight: select implementation"
$useHyperV = $false
if (Get-Command New-VHD -ErrorAction SilentlyContinue) {
    $useHyperV = $true
    Ok "Hyper-V cmdlets available, using New-VHD / Mount-VHD"
} else {
    Ok "Hyper-V cmdlets not available, using diskpart"
}

# Plan
Step "Plan"
Info "Create VHDX:    $VhdPath  size=${SizeGB}GB  dynamic"
Info "Mount VHDX"
Info "Partition:      GPT, full size"
Info "Assign letter:  $DriveLetter`:"
Info "Format:         ReFS with Dev Drive optimisations enabled"
Info ""

if ($DryRun) {
    Write-Host "DRY RUN: nothing will be changed. Re-run without -DryRun to execute." -ForegroundColor Yellow
    exit 0
}

Confirm-Or-Exit "Proceed with creation?"

# --- Execute ---

if ($useHyperV) {
    Step "Creating VHDX with New-VHD"
    $vhd = New-VHD -Path $VhdPath -SizeBytes ($SizeGB * 1GB) -Dynamic
    Ok "created $VhdPath"

    Step "Mounting VHDX"
    $disk = Mount-VHD -Path $VhdPath -Passthru | Get-Disk
    Ok "mounted as disk number $($disk.Number)"

    Step "Initialising disk"
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT
    Ok "initialised as GPT"

    Step "Creating partition"
    $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $DriveLetter
    Ok "partition assigned $DriveLetter`:"
} else {
    Step "Creating VHDX with diskpart"
    $script = @"
create vdisk file="$VhdPath" maximum=$($SizeGB * 1024) type=expandable
attach vdisk
create partition primary
assign letter=$DriveLetter
"@
    $scriptPath = [System.IO.Path]::GetTempFileName()
    $script | Out-File -FilePath $scriptPath -Encoding ascii
    diskpart /s $scriptPath | Out-Host
    Remove-Item $scriptPath -Force
    if (-not (Get-Volume -DriveLetter $DriveLetter -ErrorAction SilentlyContinue)) {
        Fail "diskpart did not produce a volume at $DriveLetter`:. Check output above."
    }
    Ok "VHDX created and partition assigned $DriveLetter`:"
}

Step "Formatting as ReFS Dev Drive"
try {
    Format-Volume -DriveLetter $DriveLetter -FileSystem ReFS -DevDrive -NewFileSystemLabel "DevDrive" -Confirm:$false -Force | Out-Null
    Ok "formatted as ReFS with Dev Drive optimisations"
} catch {
    # Older builds may not support -DevDrive on Format-Volume. Fall back to plain ReFS.
    Info "Format-Volume -DevDrive failed: $($_.Exception.Message)"
    Info "falling back to plain ReFS format (Block Cloning still works)"
    Format-Volume -DriveLetter $DriveLetter -FileSystem ReFS -NewFileSystemLabel "DevDrive" -Confirm:$false -Force | Out-Null
    Ok "formatted as ReFS (without explicit Dev Drive flag)"
}

Step "Verification"
$vol = Get-Volume -DriveLetter $DriveLetter
Info "filesystem: $($vol.FileSystem)"
Info "size:       $([Math]::Round($vol.Size/1GB,1)) GB"
Info "free:       $([Math]::Round($vol.SizeRemaining/1GB,1)) GB"
Ok "Dev Drive ready at $DriveLetter`:"

# Register the auto-mount scheduled task so the Dev Drive survives
# reboots. Without this, after the next restart the VHDX file is still
# on disk but no longer attached, and the drive letter disappears -
# which defeats the entire purpose of the setup. One task per VHDX file
# (name derived from the file basename) so multiple Dev Drives do not
# collide.
if ($SkipAutoMountTask) {
    Step "Auto-mount task: skipped (-SkipAutoMountTask)"
    Info "warning: the Dev Drive will NOT be remounted automatically on next boot."
    Info "to re-enable: re-run this script without -SkipAutoMountTask, or run"
    Info "             worktwin-light-teardown-windows -RegisterAutoMountOnly"
} else {
    Step "Registering auto-mount task for next boot"

    $vhdResolved = (Resolve-Path -LiteralPath $VhdPath).Path
    $taskName = "worktwin-mount-" + [IO.Path]::GetFileNameWithoutExtension($vhdResolved)

    # The task action invokes the worktwin-mount-helper.ps1 script that
    # ships next to this one. The helper handles both the Mount-VHD
    # path (Windows Pro / Enterprise with Hyper-V cmdlets) and the
    # diskpart fallback (Windows Home), so the task does not need to
    # know which path applies. Decoupling the logic out of the task
    # action keeps the action small and lets us debug / upgrade the
    # mount code without re-registering the task.
    $helperScript = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) 'worktwin-mount-helper.ps1'
    if (-not (Test-Path -LiteralPath $helperScript)) {
        Fail "mount helper script not found at $helperScript. Re-run the install."
    }

    $action = New-ScheduledTaskAction `
        -Execute 'powershell.exe' `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$helperScript`" -VhdPath `"$vhdResolved`""

    $trigger = New-ScheduledTaskTrigger -AtStartup

    $principal = New-ScheduledTaskPrincipal `
        -UserId 'SYSTEM' `
        -LogonType ServiceAccount `
        -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

    $description = "Re-mount the worktwin Dev Drive VHDX at $vhdResolved at every system startup, via $helperScript. Created by worktwin-light-setup-windows.ps1. To remove: worktwin-light-teardown-windows -VhdPath '$vhdResolved' -KeepFile, or Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false."

    try {
        Register-ScheduledTask `
            -TaskName $taskName `
            -Description $description `
            -Action $action `
            -Trigger $trigger `
            -Principal $principal `
            -Settings $settings `
            -Force -ErrorAction Stop | Out-Null
        Ok "scheduled task '$taskName' registered (runs as SYSTEM at startup, via worktwin-mount-helper.ps1)"
    } catch {
        Info "ERROR: Register-ScheduledTask failed: $($_.Exception.Message)"
        Info "Dev Drive will work for this session but will NOT auto-remount after a reboot."
        Info "Repair: worktwin-light-teardown-windows -RegisterAutoMountOnly -VhdPath '$vhdResolved'"
        Fail "auto-mount task registration failed; see above"
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Re-run /worktwin-light-doctor $DriveLetter`:\ inside Claude Code to confirm light mode is available." -ForegroundColor Gray
Write-Host "  2. Move or clone your large repos under $DriveLetter`:\, or configure a light-mode base mapping." -ForegroundColor Gray
if (-not $SkipAutoMountTask) {
    $taskNameForHint = "worktwin-mount-" + [IO.Path]::GetFileNameWithoutExtension($VhdPath)
    Write-Host "  3. Reboot once to verify the auto-mount task brings $DriveLetter`: back automatically." -ForegroundColor Gray
    Write-Host "     verify the task exists at any time with:" -ForegroundColor Gray
    Write-Host "       schtasks /query /TN '$taskNameForHint'" -ForegroundColor Gray
    Write-Host "     (do not use Get-ScheduledTask from a non-admin shell - it cannot see SYSTEM" -ForegroundColor Gray
    Write-Host "      tasks and returns no match silently, which looks like a false negative.)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "To remove this Dev Drive later:" -ForegroundColor Gray
Write-Host "  /worktwin-light-teardown-windows           (interactive, recommended)" -ForegroundColor Gray
Write-Host "  bin\worktwin-light-teardown-windows.ps1   (same, but bypasses Claude Code)" -ForegroundColor Gray

# If we are the elevated child (spawned via UAC), the parent terminal is
# unaware of our output - this is a new window that would close on exit.
# Pause so the user can read the log.
if ($NoElevate -and -not $NonInteractive) {
    Write-Host ""
    Read-Host "Press Enter to close this window"
}
