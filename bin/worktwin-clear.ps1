#Requires -Version 5.1
<#
worktwin-clear.ps1 - remove a stale worker's state file.

Usage:
  .\worktwin-clear.ps1 <branch>

Refuses if the worktree still exists. The branch itself is never deleted.
#>

param([Parameter(Mandatory=$true, Position=0)] [string]$Branch)

$gitCommon = & git rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommon)) {
    [Console]::Error.WriteLine("ERROR: not inside a git repository")
    exit 1
}
$gitCommon = (Resolve-Path $gitCommon).Path
$parallelDir = Join-Path $gitCommon "parallel"

$stateFile = $null
if (Test-Path $parallelDir) {
    foreach ($f in Get-ChildItem -Path $parallelDir -Filter *.json -File) {
        try {
            $state = Get-Content $f.FullName -Raw | ConvertFrom-Json
            if ($state.branch -eq $Branch) {
                $stateFile = $f.FullName
                $worktree  = $state.worktree
                break
            }
        } catch {}
    }
}

if (-not $stateFile) {
    [Console]::Error.WriteLine("ERROR: no state file found for branch '$Branch'")
    exit 1
}

if ($worktree -and (Test-Path $worktree -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: worktree still exists at $worktree")
    [Console]::Error.WriteLine("Run /worktwin-ship $Branch or /worktwin-finalize $Branch first,")
    [Console]::Error.WriteLine("or 'git worktree remove $worktree' to drop it manually.")
    exit 1
}

Remove-Item -Path $stateFile -Force
Write-Host "removed stale state: $stateFile"

& git worktree prune 2>$null
