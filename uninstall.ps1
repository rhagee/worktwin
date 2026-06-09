#Requires -Version 5.1

param(
    [string]$Mode = "global"
)

switch ($Mode) {
    "global" {
        $Target = Join-Path $env:USERPROFILE ".claude\skills"
    }
    "local" {
        $RepoRoot = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RepoRoot)) {
            Write-Host "ERROR: 'local' mode requires running inside a git repo"
            exit 1
        }
        $Target = Join-Path $RepoRoot ".claude\skills"
    }
    default {
        $Target = Join-Path $Mode ".claude\skills"
    }
}

$Skills = @(
    "worktwin",
    "worktwin-ship",
    "worktwin-ship-all",
    "worktwin-finalize",
    "worktwin-status",
    "worktwin-help"
)

foreach ($Skill in $Skills) {
    $Dest = Join-Path $Target $Skill
    if (Test-Path $Dest) {
        Remove-Item -Path $Dest -Recurse -Force
    }
}

Write-Host "worktwin removed from $Target"
