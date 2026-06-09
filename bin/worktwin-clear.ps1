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
    [switch]$Force,
    [switch]$All
)

if (-not $All -and -not $Branch) {
    [Console]::Error.WriteLine("usage: worktwin-clear [-Force] <branch>  OR  worktwin-clear -All [-Force]")
    exit 2
}
if ($All -and $Branch) {
    [Console]::Error.WriteLine("ERROR: do not combine -All with a branch name")
    exit 2
}

$gitCommon = & git rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommon)) {
    [Console]::Error.WriteLine("ERROR: not inside a git repository")
    exit 1
}
$gitCommon = (Resolve-Path $gitCommon).Path
$parallelDir = Join-Path $gitCommon "parallel"

function Clear-One($file) {
    try {
        $state = Get-Content $file -Raw | ConvertFrom-Json
    } catch {
        return @{ ok = $false; reason = "could not parse state file" }
    }
    $worktree = $state.worktree
    if ($worktree -and (Test-Path $worktree -PathType Container)) {
        $uncommitted = 0
        try {
            $st = & git -C $worktree status --porcelain 2>$null
            if ($LASTEXITCODE -eq 0 -and $st) {
                $uncommitted = ($st | Measure-Object -Line).Lines
            }
        } catch {}
        if ($uncommitted -gt 0 -and -not $Force) {
            Write-Host "SKIP $($state.branch) ($worktree has $uncommitted uncommitted change(s))"
            return @{ ok = $false; reason = "dirty" }
        }
        if ($Force) {
            & git worktree remove --force $worktree 2>$null | Out-Null
            if (Test-Path $worktree) {
                Remove-Item -Path $worktree -Recurse -Force -ErrorAction SilentlyContinue
            }
        } else {
            & git worktree remove $worktree 2>$null | Out-Null
        }
        Write-Host "removed worktree: $worktree"
    }
    Remove-Item -Path $file -Force
    Write-Host "removed state: $file"
    return @{ ok = $true }
}

if ($All) {
    if (-not (Test-Path $parallelDir)) {
        Write-Host "no active workers"
        exit 0
    }
    $cleared = 0
    $skipped = 0
    foreach ($f in Get-ChildItem -Path $parallelDir -Filter *.json -File) {
        $res = Clear-One $f.FullName
        if ($res.ok) { $cleared++ } else { $skipped++ }
    }
    Write-Host ""
    if ($skipped -gt 0) {
        Write-Host "summary: $cleared cleared, $skipped skipped (re-run with -Force to discard their uncommitted work)"
    } else {
        Write-Host "summary: $cleared cleared"
    }
    & git worktree prune 2>$null
    exit 0
}

# Single-branch mode
$stateFile = $null
if (Test-Path $parallelDir) {
    foreach ($f in Get-ChildItem -Path $parallelDir -Filter *.json -File) {
        try {
            $state = Get-Content $f.FullName -Raw | ConvertFrom-Json
            if ($state.branch -eq $Branch) {
                $stateFile = $f.FullName
                break
            }
        } catch {}
    }
}

if (-not $stateFile) {
    [Console]::Error.WriteLine("ERROR: no state file found for branch '$Branch'")
    exit 1
}

$res = Clear-One $stateFile
if (-not $res.ok) {
    [Console]::Error.WriteLine("Commit, stash, or pass -Force to discard.")
    exit 1
}

& git worktree prune 2>$null
