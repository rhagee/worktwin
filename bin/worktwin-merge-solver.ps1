#Requires -Version 5.1
<#
worktwin-merge-solver.ps1 - cross-PR conflict resolution toolkit.
Mirror of bin/worktwin-merge-solver. Each subcommand is one atomic
operation. The skill orchestrates and lets the agent drive the
conversation and actual conflict resolution.

Usage:
  .\worktwin-merge-solver.ps1 <subcommand> [args]

Subcommands:
  discover         scan workers, group by base, report conflicts
  prepare          create the combined worktree for one base group
  merge-step       attempt `git merge <child>` into the combined worktree
  finalize-step    commit a resolved merge step
  push             push the combined branch
  open-pr          open the combined PR via gh
  close-original   close superseded child PRs via gh

JSON on stdout for every subcommand. Errors on stderr, non-zero exit.
#>

param(
    [Parameter(Position=0, Mandatory=$true)] [string]$Subcommand,
    [Parameter(ValueFromRemainingArguments=$true)] [string[]]$Args
)

function Fail($msg) {
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}

function Out-Json($obj) {
    $obj | ConvertTo-Json -Depth 12 -Compress
}

function Slug([string]$s) {
    if ([string]::IsNullOrEmpty($s)) { return '' }
    $r = [regex]::Replace($s, '[^A-Za-z0-9._-]+', '-')
    $r = $r.Trim('-')
    return $r
}

function Require-GitRepo {
    & git rev-parse --git-common-dir 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "not inside a git repository" }
}

function Get-BinDir { return $PSScriptRoot }

function Resolve-Worker([string]$branch) {
    $listScript = Join-Path (Get-BinDir) 'worktwin-list.ps1'
    if (-not (Test-Path $listScript)) { Fail "worktwin-list.ps1 missing next to worktwin-merge-solver.ps1" }
    $lines = & pwsh -NoProfile -ExecutionPolicy Bypass -File $listScript $branch 2>$null
    if (-not $lines) {
        # PS 5.1 fallback - the user might not have pwsh on PATH
        $lines = & powershell -NoProfile -ExecutionPolicy Bypass -File $listScript $branch 2>$null
    }
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $obj = $line | ConvertFrom-Json
            if ($obj.branch -eq $branch) { return $obj }
        } catch { }
    }
    return $null
}

# ---------------- discover ----------------------------------------------

function Cmd-Discover([string[]]$Argv) {
    Require-GitRepo
    if ($Argv.Count -lt 1) {
        Fail "usage: worktwin-merge-solver discover <branch> [<branch> ...]"
    }

    $resolved = New-Object System.Collections.ArrayList
    $missing  = New-Object System.Collections.ArrayList

    foreach ($b in $Argv) {
        $w = Resolve-Worker $b
        if (-not $w) {
            [void]$missing.Add($b)
            continue
        }
        $wtMd = ''
        $worktreePath = $w.worktree
        if ($worktreePath -and (Test-Path (Join-Path $worktreePath 'WORKTWIN.md'))) {
            $wtMd = (Join-Path $worktreePath 'WORKTWIN.md')
        }
        $commits = New-Object System.Collections.ArrayList
        & git rev-parse --verify $b 2>$null | Out-Null
        $bOk = ($LASTEXITCODE -eq 0)
        & git rev-parse --verify $w.from_branch 2>$null | Out-Null
        $fromOk = ($LASTEXITCODE -eq 0)
        if ($bOk -and $fromOk) {
            $log = & git log --format='%H%x09%s' "$($w.from_branch)..$b" 2>$null
            foreach ($line in $log) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $parts = $line -split "`t", 2
                [void]$commits.Add(@{ sha = $parts[0]; subject = if ($parts.Count -gt 1) { $parts[1] } else { '' } })
            }
        }
        $w | Add-Member -NotePropertyName worktwin_md -NotePropertyValue $wtMd -Force
        $w | Add-Member -NotePropertyName commits     -NotePropertyValue $commits.ToArray() -Force
        [void]$resolved.Add($w)
    }

    # Group by from_branch preserving input order.
    $groups = New-Object System.Collections.ArrayList
    $seenBases = New-Object System.Collections.Generic.HashSet[string]
    foreach ($w in $resolved) {
        $base = $w.from_branch
        if ($seenBases.Contains($base)) { continue }
        [void]$seenBases.Add($base)
        $children = @($resolved | Where-Object { $_.from_branch -eq $base })
        [void]$groups.Add([pscustomobject]@{
            base = $base
            children = $children
            conflicts = @()
            status = 'unknown'
            base_ref = $null
        })
    }

    foreach ($g in $groups) {
        if ($g.children.Count -le 1) {
            $g.status = 'alone'
            continue
        }

        & git rev-parse --verify $g.base 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            & git fetch --quiet origin $g.base 2>$null | Out-Null
        }
        & git rev-parse --verify $g.base 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $g.base_ref = $g.base
        } else {
            $g.base_ref = "origin/$($g.base)"
        }

        $conflicts = New-Object System.Collections.ArrayList
        for ($i = 0; $i -lt $g.children.Count; $i++) {
            for ($j = $i + 1; $j -lt $g.children.Count; $j++) {
                $A = $g.children[$i].branch
                $B = $g.children[$j].branch
                $mt = & git merge-tree --write-tree "--merge-base=$($g.base_ref)" $A $B 2>$null
                $files = @()
                foreach ($line in $mt) {
                    if ($line -match '^CONFLICT.* in (.+)$') {
                        $files += $Matches[1]
                    }
                }
                $files = $files | Sort-Object -Unique
                if ($files.Count -gt 0) {
                    [void]$conflicts.Add([pscustomobject]@{ a = $A; b = $B; files = $files })
                }
            }
        }
        $g.conflicts = $conflicts.ToArray()
        $g.status = if ($conflicts.Count -gt 0) { 'conflicting' } else { 'clean' }
    }

    Out-Json @{
        input_order = $Argv
        workers     = $resolved.ToArray()
        groups      = $groups.ToArray()
        missing     = $missing.ToArray()
    }
}

# ---------------- prepare -----------------------------------------------

function Cmd-Prepare([string[]]$Argv) {
    Require-GitRepo
    $name = ''
    $rest = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -like '--name=*') { $name = $a.Substring(7) }
        else { [void]$rest.Add($a) }
    }
    if ($rest.Count -lt 2) {
        Fail "usage: worktwin-merge-solver prepare <base> <child> [<child> ...] [--name=<combined>]"
    }
    $base = $rest[0]
    $children = $rest[1..($rest.Count - 1)]

    & git fetch --quiet origin $base 2>$null | Out-Null
    $baseRef = $null
    & git rev-parse --verify "origin/$base" 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $baseRef = "origin/$base" }
    else {
        & git rev-parse --verify $base 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $baseRef = $base }
    }
    if (-not $baseRef) { Fail "base branch '$base' not found locally or on origin" }

    if ([string]::IsNullOrEmpty($name)) {
        $childrenSlug = ($children | ForEach-Object { Slug $_ }) -join '+'
        $name = "worktwin-merge/$(Slug $base)/$childrenSlug"
    }

    & git rev-parse --verify $name 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Fail "combined branch '$name' already exists. Pass a different --name= or delete it first."
    }

    $gitCommonDir = (& git rev-parse --git-common-dir).Trim()
    $gitCommonDir = (Resolve-Path $gitCommonDir).Path
    $mainRepo = (Resolve-Path (Split-Path $gitCommonDir -Parent)).Path
    $repoName = Split-Path $mainRepo -Leaf
    $nameSlug = Slug $name
    $parent = Split-Path $mainRepo -Parent
    $combinedWorktree = Join-Path $parent "$repoName--merge-$nameSlug"

    if (Test-Path $combinedWorktree) {
        Fail "combined worktree path already exists: $combinedWorktree"
    }

    & git worktree add -q -b $name $combinedWorktree $baseRef 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "git worktree add failed" }

    Out-Json @{
        combined_branch   = $name
        combined_worktree = $combinedWorktree
        base              = $base
        base_ref          = $baseRef
        children          = $children
    }
}

# ---------------- merge-step --------------------------------------------

function Cmd-MergeStep([string[]]$Argv) {
    Require-GitRepo
    if ($Argv.Count -lt 2) {
        Fail "usage: worktwin-merge-solver merge-step <combined-worktree> <child>"
    }
    $wt = $Argv[0]; $child = $Argv[1]
    if (-not (Test-Path $wt -PathType Container)) { Fail "combined worktree not found: $wt" }

    & git -C $wt rev-parse --verify $child 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & git -C $wt fetch --quiet origin $child 2>$null | Out-Null
    }
    & git -C $wt rev-parse --verify $child 2>$null | Out-Null
    $childRef = $null
    if ($LASTEXITCODE -eq 0) { $childRef = $child }
    else {
        & git -C $wt rev-parse --verify "origin/$child" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $childRef = "origin/$child" }
    }
    if (-not $childRef) { Fail "child branch '$child' not found locally or on origin" }

    & git -C $wt merge --no-ff --no-commit $childRef 2>$null | Out-Null
    $rc = $LASTEXITCODE

    $conflicting = @()
    if ($rc -ne 0) {
        $files = & git -C $wt diff --name-only --diff-filter=U 2>$null
        $conflicting = @($files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $status = if ($conflicting.Count -gt 0) { 'conflict' } else { 'clean' }
    Out-Json @{
        status            = $status
        child             = $child
        child_ref         = $childRef
        conflicting_files = $conflicting
    }
}

# ---------------- finalize-step -----------------------------------------

function Cmd-FinalizeStep([string[]]$Argv) {
    Require-GitRepo
    $msg = ''
    $rest = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -like '--message=*') { $msg = $a.Substring(10) }
        else { [void]$rest.Add($a) }
    }
    if ($rest.Count -lt 1 -or [string]::IsNullOrEmpty($msg)) {
        Fail "usage: worktwin-merge-solver finalize-step <combined-worktree> --message=<m>"
    }
    $wt = $rest[0]
    if (-not (Test-Path $wt -PathType Container)) { Fail "combined worktree not found: $wt" }

    & git -C $wt diff --check 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "unresolved conflict markers present in $wt" }

    & git -C $wt add -A 2>$null | Out-Null
    & git -C $wt commit -q -m $msg 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "git commit failed in $wt" }
    $sha = (& git -C $wt rev-parse HEAD).Trim()
    Out-Json @{ sha = $sha; message = $msg }
}

# ---------------- push --------------------------------------------------

function Cmd-Push([string[]]$Argv) {
    Require-GitRepo
    $remote = 'origin'
    $rest = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -like '--remote=*') { $remote = $a.Substring(9) }
        else { [void]$rest.Add($a) }
    }
    if ($rest.Count -lt 1) {
        Fail "usage: worktwin-merge-solver push <combined-worktree> [--remote=<r>]"
    }
    $wt = $rest[0]
    if (-not (Test-Path $wt -PathType Container)) { Fail "combined worktree not found: $wt" }
    $branch = (& git -C $wt rev-parse --abbrev-ref HEAD).Trim()
    & git -C $wt push -u $remote $branch
    if ($LASTEXITCODE -ne 0) { Fail "git push failed" }
    Out-Json @{ remote = $remote; branch = $branch }
}

# ---------------- open-pr -----------------------------------------------

function Cmd-OpenPr([string[]]$Argv) {
    Require-GitRepo
    $base = ''; $title = ''; $body = ''; $draft = $false
    $rest = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        switch -Regex ($a) {
            '^--base=(.+)'  { $base  = $Matches[1]; continue }
            '^--title=(.+)' { $title = $Matches[1]; continue }
            '^--body=(.+)'  { $body  = $Matches[1]; continue }
            '^--draft$'     { $draft = $true; continue }
            default         { [void]$rest.Add($a) }
        }
    }
    if ($rest.Count -lt 1 -or [string]::IsNullOrEmpty($base) -or [string]::IsNullOrEmpty($title)) {
        Fail "usage: worktwin-merge-solver open-pr <combined-worktree> --base=<b> --title=<t> --body=<f> [--draft]"
    }
    $wt = $rest[0]
    if (-not (Test-Path $wt -PathType Container)) { Fail "combined worktree not found: $wt" }
    & gh --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "gh is missing" }
    & gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "gh is unauthenticated" }

    $head = (& git -C $wt rev-parse --abbrev-ref HEAD).Trim()
    Push-Location $wt
    try {
        $ghArgs = @('pr', 'create', '--base', $base, '--head', $head, '--title', $title, '--body', $body)
        if ($draft) { $ghArgs += '--draft' }
        $url = & gh @ghArgs 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Fail "gh pr create failed: $url"
        }
        $url = $url.Trim()
    } finally {
        Pop-Location
    }
    $num = $null
    if ($url -match '/pull/(\d+)') { $num = [int]$Matches[1] }
    if ($null -eq $num) {
        Push-Location $wt
        try {
            $listJson = & gh pr list --head $head --json number 2>$null | Out-String
            if ($LASTEXITCODE -eq 0 -and $listJson) {
                $arr = $listJson | ConvertFrom-Json
                if ($arr -and $arr.Count -gt 0) { $num = $arr[0].number }
            }
        } finally { Pop-Location }
    }
    Out-Json @{ url = $url; number = $num; head = $head }
}

# ---------------- close-original ----------------------------------------

function Cmd-CloseOriginal([string[]]$Argv) {
    $superseded = ''
    $prs = New-Object System.Collections.ArrayList
    foreach ($a in $Argv) {
        if ($a -like '--superseded-by=*') { $superseded = $a.Substring(16) }
        else { [void]$prs.Add($a) }
    }
    if ([string]::IsNullOrEmpty($superseded) -or $prs.Count -eq 0) {
        Fail "usage: worktwin-merge-solver close-original <pr-num> [<pr-num> ...] --superseded-by=<n>"
    }
    & gh --version 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "gh is missing" }
    & gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Fail "gh is unauthenticated" }

    $comment = "Superseded by #$superseded (combined via worktwin-merge-solver). The branch and history are preserved."
    $results = New-Object System.Collections.ArrayList
    foreach ($pr in $prs) {
        $ok = $true; $err = ''
        & gh pr comment $pr --body $comment 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $ok = $false; $err = 'comment failed' }
        & gh pr close $pr 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            $ok = $false
            if ($err) { $err = "$err; close failed" } else { $err = 'close failed' }
        }
        $prNum = $null
        if ($pr -match '^\d+$') { $prNum = [int]$pr }
        [void]$results.Add(@{ pr = $prNum; closed = $ok; error = $err })
    }
    $supNum = $null
    if ($superseded -match '^\d+$') { $supNum = [int]$superseded }
    Out-Json @{ superseded_by = $supNum; results = $results.ToArray() }
}

# ---------------- dispatch ----------------------------------------------

switch ($Subcommand) {
    'discover'        { Cmd-Discover       $Args }
    'prepare'         { Cmd-Prepare        $Args }
    'merge-step'      { Cmd-MergeStep      $Args }
    'finalize-step'   { Cmd-FinalizeStep   $Args }
    'push'            { Cmd-Push           $Args }
    'open-pr'         { Cmd-OpenPr         $Args }
    'close-original'  { Cmd-CloseOriginal  $Args }
    '-h'              { Get-Help $PSCommandPath -Full }
    '--help'          { Get-Help $PSCommandPath -Full }
    'help'            { Get-Help $PSCommandPath -Full }
    default {
        [Console]::Error.WriteLine("ERROR: unknown subcommand: $Subcommand")
        exit 2
    }
}
