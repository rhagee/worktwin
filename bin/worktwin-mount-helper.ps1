#Requires -Version 5.1
<#
worktwin-mount-helper.ps1 - mount a worktwin Dev Drive VHDX at boot.
Idempotent. Agnostic to Hyper-V availability: uses Mount-VHD when the
Hyper-V cmdlets are present, falls back to diskpart on systems where
they are not (Windows 11 Home, server Core without the Hyper-V module,
etc.).

This script is invoked at system startup by the worktwin-mount-<name>
scheduled task created by worktwin-light-setup-windows.ps1 or by
worktwin-light-teardown-windows.ps1 -RegisterAutoMountOnly. The task
runs it as SYSTEM with the only argument being the VHDX path.

Exit codes:
  0 - VHDX missing on disk (silently no-op), already attached, or
      mount attempt completed (success or failure). We never fail
      loudly here because the task fires at boot and a non-zero exit
      would just confuse the Event Log.
#>

param(
    [Parameter(Mandatory=$true)] [string]$VhdPath
)

# If the user deleted the VHDX, nothing to do. Stay silent.
if (-not (Test-Path -LiteralPath $VhdPath)) { exit 0 }

# If a File Backed Virtual disk is already attached and reports the
# same backing file, we are done. The mapping between Get-Disk and the
# VHDX path is not directly available without Hyper-V cmdlets; we use a
# best-effort heuristic: any FBV disk already online means the most
# common single-Dev-Drive setup is satisfied. Both Mount-VHD and the
# diskpart attach below are idempotent enough to tolerate the rare
# multi-VHDX edge case (they error on already-attached, we swallow).
$alreadyAttached = $false
try {
    $fbv = Get-Disk -ErrorAction SilentlyContinue | Where-Object { $_.BusType -eq 'File Backed Virtual' -and $_.OperationalStatus -eq 'Online' }
    if ($fbv) { $alreadyAttached = $true }
} catch { }

if (Get-Command Mount-VHD -ErrorAction SilentlyContinue) {
    try {
        if (-not (Get-VHD -Path $VhdPath -ErrorAction SilentlyContinue).Attached) {
            Mount-VHD -Path $VhdPath -ErrorAction SilentlyContinue | Out-Null
        }
    } catch { }
    exit 0
}

# Hyper-V cmdlets missing - use diskpart. attach vdisk is idempotent
# enough: diskpart prints an error if the disk is already attached but
# returns 0, which is exactly what we want.
if ($alreadyAttached) { exit 0 }

$diskpartScript = @"
select vdisk file="$VhdPath"
attach vdisk
"@
$tmp = [System.IO.Path]::GetTempFileName()
try {
    Set-Content -Path $tmp -Value $diskpartScript -Encoding ascii
    $null = & diskpart /s $tmp 2>&1
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
exit 0
