#Requires -Version 5.1
<#
worktwin-list.ps1 - discover worktwin workers and emit one JSON per line.

Usage:
  .\worktwin-list.ps1                            # list all
  .\worktwin-list.ps1 feat/auth feat/payments    # filter
#>

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$Filter
)

$gitCommon = & git rev-parse --git-common-dir 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitCommon)) {
    [Console]::Error.WriteLine("ERROR: not inside a git repository")
    exit 1
}
$gitCommon = (Resolve-Path $gitCommon).Path
$parallelDir = Join-Path $gitCommon "parallel"
if (-not (Test-Path $parallelDir)) { exit 0 }

$files = Get-ChildItem -Path $parallelDir -Filter *.json -File -ErrorAction SilentlyContinue
foreach ($f in $files) {
    try {
        $state = Get-Content $f.FullName -Raw | ConvertFrom-Json
    } catch {
        [Console]::Error.WriteLine("WARN: could not parse $($f.Name)")
        continue
    }

    if ($Filter -and ($Filter.Count -gt 0) -and -not ($Filter -contains $state.branch)) {
        continue
    }

    $exists = $false
    $commitsAhead = 0
    $filesChanged = 0
    $uncommitted  = 0

    if (Test-Path $state.worktree -PathType Container) {
        $exists = $true
        $range  = "$($state.from_branch)..$($state.branch)"
        $log    = & git -C $state.worktree log $range --oneline 2>$null
        if ($LASTEXITCODE -eq 0 -and $log) { $commitsAhead = ($log | Measure-Object -Line).Lines }
        $diff   = & git -C $state.worktree diff --name-only $range 2>$null
        if ($LASTEXITCODE -eq 0 -and $diff) { $filesChanged = ($diff | Measure-Object -Line).Lines }
        $st     = & git -C $state.worktree status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and $st)   { $uncommitted  = ($st  | Measure-Object -Line).Lines }
    }

    $out = [ordered]@{
        branch          = $state.branch
        from_branch     = $state.from_branch
        worktree        = $state.worktree
        task            = $state.task
        started_at      = $state.started_at
        status          = $state.status
        worktree_exists = $exists
        commits_ahead   = $commitsAhead
        files_changed   = $filesChanged
        uncommitted     = $uncommitted
    }
    $out | ConvertTo-Json -Depth 4 -Compress
}
