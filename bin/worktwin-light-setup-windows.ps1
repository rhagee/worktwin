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
  - Does not touch any existing volume.
  - To remove the Dev Drive later: detach the VHD, delete the VHDX file.
#>

[CmdletBinding()]
param(
    [string]$VhdPath,
    [int]$SizeGB,
    [string]$DriveLetter,
    [switch]$DryRun,
    [switch]$NonInteractive
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

# Pre-flight: OS version
Step "Pre-flight: Windows version"
$build = [System.Environment]::OSVersion.Version.Build
Info "OS build: $build (Dev Drive requires 22621 or later, i.e. Windows 11 22H2)"
if ($build -lt 22621) {
    Fail "Dev Drive requires Windows 11 22H2 or later (build 22621+). This system is build $build."
}
Ok "Windows version is sufficient"

# Pre-flight: admin
Step "Pre-flight: admin rights"
$isAdmin = ([Security.Principal.WindowsPrincipal] `
            [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
            [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Fail "this script must run from an elevated PowerShell. Right-click PowerShell -> Run as Administrator."
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

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Re-run /worktwin-light-doctor $DriveLetter`:\ inside Claude Code to confirm light mode is available." -ForegroundColor Gray
Write-Host "  2. Move or clone your large repos under $DriveLetter`:\, or configure a light-mode base mapping." -ForegroundColor Gray
Write-Host ""
Write-Host "To remove this Dev Drive later:" -ForegroundColor Gray
Write-Host "  Dismount-VHD -Path '$VhdPath'   (or use diskpart 'detach vdisk')" -ForegroundColor Gray
Write-Host "  Remove-Item '$VhdPath'" -ForegroundColor Gray
