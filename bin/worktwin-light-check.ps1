#Requires -Version 5.1
<#
worktwin-light-check.ps1 - detect whether a Windows path lives on a
filesystem that supports copy-on-write file cloning (ReFS Block
Cloning). Used by worktwin to decide if light mode is available.

Usage:
  .\worktwin-light-check.ps1 [path]

Output schema mirrors the bash version, plus a Windows-specific
`dev_drives` array listing every ReFS volume currently mounted on
the system.
#>

param([string]$Path)

if (-not $Path) { $Path = (Get-Location).Path }

$absPath = $null
try {
    $absPath = (Resolve-Path $Path -ErrorAction Stop).Path
} catch {
    $absPath = $Path
}

# Derive the drive letter from the absolute path
$qualifier = Split-Path -Qualifier $absPath -ErrorAction SilentlyContinue
if (-not $qualifier) {
    $result = [ordered]@{
        os             = "windows"
        filesystem     = "unknown"
        cow_capable    = $false
        path           = $absPath
        reason         = "could not derive a drive letter from path"
        recommendation = "filesystem-not-supported"
        dev_drives     = @()
    }
    $result | ConvertTo-Json -Compress
    exit 0
}

$driveLetter = $qualifier.TrimEnd(':')

$volume = $null
try {
    $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop
} catch {}

# List every ReFS volume on the machine so the doctor can suggest one
# if the current path is on NTFS.
$devDrives = @()
try {
    Get-Volume -ErrorAction Stop |
        Where-Object { $_.FileSystem -eq "ReFS" -and $_.DriveLetter } |
        ForEach-Object { $devDrives += "$($_.DriveLetter):\" }
} catch {}

$fs = if ($volume) { $volume.FileSystem } else { "unknown" }
$cow = $false
$reason = ""
$recommendation = "filesystem-not-supported"

switch ($fs) {
    "ReFS" {
        $cow = $true
        $reason = "ReFS supports Block Cloning"
        $recommendation = "ready"
    }
    "NTFS" {
        $reason = "NTFS does not support Block Cloning"
        if ($devDrives.Count -gt 0) {
            $recommendation = "switch-path"
        } else {
            $recommendation = "create-volume"
        }
    }
    "exFAT" {
        $reason = "exFAT does not support Block Cloning"
        if ($devDrives.Count -gt 0) { $recommendation = "switch-path" } else { $recommendation = "create-volume" }
    }
    "FAT32" {
        $reason = "FAT32 does not support Block Cloning"
        if ($devDrives.Count -gt 0) { $recommendation = "switch-path" } else { $recommendation = "create-volume" }
    }
    default {
        $reason = "filesystem '$fs' not recognised as CoW-capable"
        if ($devDrives.Count -gt 0) { $recommendation = "switch-path" } else { $recommendation = "create-volume" }
    }
}

$result = [ordered]@{
    os             = "windows"
    filesystem     = $fs
    cow_capable    = $cow
    path           = $absPath
    reason         = $reason
    recommendation = $recommendation
    dev_drives     = $devDrives
}
$result | ConvertTo-Json -Compress
