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

$Src = Join-Path $PSScriptRoot "skills"
if (-not (Test-Path $Src)) {
    Write-Host "ERROR: skills/ directory not found at $Src"
    exit 1
}

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

$Skills = @(
    "worktwin",
    "worktwin-ship",
    "worktwin-ship-all",
    "worktwin-finalize",
    "worktwin-status",
    "worktwin-clear",
    "worktwin-light-doctor",
    "worktwin-help",
    "worktwin-update"
)

foreach ($Skill in $Skills) {
    $Dest = Join-Path $Target $Skill
    if (Test-Path $Dest) {
        Remove-Item -Path $Dest -Recurse -Force
    }
    Copy-Item -Path (Join-Path $Src $Skill) -Destination $Target -Recurse -Force
}

$BinSrc = Join-Path $PSScriptRoot "bin"
if (Test-Path $BinSrc) {
    $BinDst = Join-Path $Target "worktwin\bin"
    if (-not (Test-Path $BinDst)) { New-Item -ItemType Directory -Path $BinDst -Force | Out-Null }
    Copy-Item -Path (Join-Path $BinSrc "*") -Destination $BinDst -Recurse -Force
}

# Record where this clone lives so worktwin-update can find it later.
# Forward slashes so the path is consumable by both PowerShell and bash
# (Git Bash on Windows does not understand backslash paths in test -d).
# UTF-8 without BOM so bash does not read a stray zero-width character
# at the start of the path (Set-Content -Encoding utf8 on 5.1 adds a BOM).
$SourceFile = Join-Path $Target "worktwin\.source"
$NormalisedPath = $PSScriptRoot -replace '\\', '/'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($SourceFile, $NormalisedPath, $Utf8NoBom)

Write-Host "worktwin installed to $Target"
Write-Host ""
Write-Host "Run /worktwin-help inside Claude Code to see every command."
Write-Host "Standalone CLI tools at $Target\worktwin\bin"
