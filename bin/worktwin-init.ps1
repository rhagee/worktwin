#Requires -Version 5.1
<#
worktwin-init.ps1 - atomic spawn of a worktwin parallel worker.
Pluggable: usable from any skill or directly from PowerShell.

Usage:
  .\worktwin-init.ps1 <from-branch> <new-branch> "<task>"

Prints a JSON object on stdout. Exits non-zero on any error.
#>

param(
    [Parameter(Mandatory=$true, Position=0)] [string]$FromBranch,
    [Parameter(Mandatory=$true, Position=1)] [string]$NewBranch,
    [Parameter(Mandatory=$true, Position=2)] [string]$Task
)

function Fail($msg) {
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}

$gitCommon = & git rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommon)) {
    Fail "not inside a git repository"
}
$gitCommon = (Resolve-Path $gitCommon).Path
$mainRepo  = (Resolve-Path (Join-Path $gitCommon "..")).Path
$repoName  = Split-Path -Leaf $mainRepo

$slug = ($NewBranch -replace '[^a-zA-Z0-9._-]', '-')
$worktreePath = Join-Path (Split-Path -Parent $mainRepo) ("$repoName--$slug")

$warnings = @()
$currentTop = & git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { Fail "git rev-parse --show-toplevel failed" }
if ((Resolve-Path $currentTop).Path -ne $mainRepo) {
    $warnings += "invoked from a worktree, using main repo as base"
}

# Resolve from_branch (fetch fallback)
& git rev-parse --verify $FromBranch *> $null
if ($LASTEXITCODE -eq 0) {
    $fromRef = $FromBranch
} else {
    & git fetch origin $FromBranch *> $null
    & git rev-parse --verify "origin/$FromBranch" *> $null
    if ($LASTEXITCODE -eq 0) {
        $fromRef = "origin/$FromBranch"
    } else {
        Fail "source branch '$FromBranch' not found locally or on origin"
    }
}

if (Test-Path $worktreePath) {
    $registered = (& git worktree list --porcelain) -match "^worktree $([regex]::Escape($worktreePath))$"
    if (-not $registered) {
        Fail "$worktreePath exists but is not a registered worktree"
    }
    $warnings += "worktree already registered, reusing"
} else {
    & git rev-parse --verify $NewBranch *> $null
    if ($LASTEXITCODE -eq 0) {
        & git worktree add $worktreePath $NewBranch *> $null
    } else {
        & git worktree add -b $NewBranch $worktreePath $fromRef *> $null
    }
    if ($LASTEXITCODE -ne 0) { Fail "git worktree add failed" }
}

$parallelDir = Join-Path $gitCommon "parallel"
if (-not (Test-Path $parallelDir)) { New-Item -ItemType Directory -Path $parallelDir -Force | Out-Null }
$stateFile = Join-Path $parallelDir "$slug.json"
$startedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$state = [ordered]@{
    branch      = $NewBranch
    from_branch = $FromBranch
    worktree    = $worktreePath
    task        = $Task
    started_at  = $startedAt
    status      = "active"
}
$state | ConvertTo-Json -Depth 4 | Set-Content -Path $stateFile -Encoding utf8

$output = [ordered]@{
    main_repo   = $mainRepo
    worktree    = $worktreePath
    branch      = $NewBranch
    from_branch = $FromBranch
    from_ref    = $fromRef
    state_file  = $stateFile
    warnings    = $warnings
}
$output | ConvertTo-Json -Depth 4
