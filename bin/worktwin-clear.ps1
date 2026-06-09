#Requires -Version 5.1
<#
worktwin-clear.ps1 - remove a worker's worktree directory and state
file. Safe by default: refuses when uncommitted changes exist unless
--force is passed.

Usage:
  .\worktwin-clear.ps1 [-Force] <branch>
#>

param(
    [Parameter(Position=0)] [string]$Branch,
    [switch]$Force
)

if (-not $Branch) {
    [Console]::Error.WriteLine("usage: worktwin-clear [-Force] <branch>")
    exit 2
}

$gitCommon = & git rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommon)) {
    [Console]::Error.WriteLine("ERROR: not inside a git repository")
    exit 1
}
$gitCommon = (Resolve-Path $gitCommon).Path
$parallelDir = Join-Path $gitCommon "parallel"

$stateFile = $null
$worktree = $null
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
    $uncommitted = 0
    try {
        $st = & git -C $worktree status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and $st) {
            $uncommitted = ($st | Measure-Object -Line).Lines
        }
    } catch {}

    if ($uncommitted -gt 0 -and -not $Force) {
        [Console]::Error.WriteLine("ERROR: worktree at $worktree has $uncommitted uncommitted change(s)")
        [Console]::Error.WriteLine("Commit or stash them first, or pass -Force to discard.")
        exit 1
    }

    if ($Force) {
        & git worktree remove --force $worktree 2>$null
        if (-not (Test-Path $worktree)) {
            # ok
        } else {
            Remove-Item -Path $worktree -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        & git worktree remove $worktree
    }
    Write-Host "removed worktree: $worktree"
}

Remove-Item -Path $stateFile -Force
Write-Host "removed state: $stateFile"

& git worktree prune 2>$null
