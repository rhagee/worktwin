#Requires -Version 5.1
<#
worktwin-light-clone.ps1 - copy top-level entries from <Src> to <Dst>
excluding .git, using ReFS Block Cloning where possible.

Copy-Item on Windows uses CopyFile2 under the hood, which calls into
the volume's CoW path when both source and destination live on the
same ReFS volume. No special flag needed.
#>

param(
    [Parameter(Mandatory=$true)] [string]$Src,
    [Parameter(Mandatory=$true)] [string]$Dst
)

if (-not (Test-Path $Src -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: source not found: $Src")
    exit 1
}
if (-not (Test-Path $Dst -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: destination not found: $Dst")
    exit 1
}

Get-ChildItem -Path $Src -Force -ErrorAction Stop |
    Where-Object { $_.Name -ne ".git" } |
    ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $Dst -Recurse -Force -ErrorAction Stop
    }
