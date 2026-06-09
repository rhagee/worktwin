#Requires -Version 5.1
<#
update.ps1 - git pull the worktwin repo, then re-run install.ps1.
Run from inside the cloned worktwin repo.
#>

param([string]$Mode = "global")

$RepoRoot = $PSScriptRoot
Set-Location $RepoRoot

Write-Host "Updating worktwin from $RepoRoot"

& git rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("ERROR: $RepoRoot is not a git repository. Run update.ps1 from the cloned worktwin repo.")
    exit 1
}

$skipPull = $false
$dirty = & git status --porcelain
if ($dirty) {
    Write-Host "WARN: $RepoRoot has uncommitted changes. Skipping git pull, re-running install only."
    $skipPull = $true
}

if (-not $skipPull) {
    Write-Host "git pull..."
    & git pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("ERROR: git pull failed. Resolve manually, then re-run update.ps1.")
        exit 1
    }
}

& "$RepoRoot\install.ps1" $Mode
Write-Host ""
Write-Host "worktwin updated. Restart Claude Code to pick up the new skills."
