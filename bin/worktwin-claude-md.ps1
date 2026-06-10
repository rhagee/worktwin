#Requires -Version 5.1
<#
worktwin-claude-md.ps1 - set up the worktwin parallel-worker context in
a worktree. Writes WORKTWIN.md with the full rules and task, appends a
small reference block at the bottom of CLAUDE.md, and marks both files
so git will not pick them up for commits.

Usage:
  .\worktwin-claude-md.ps1 <worktree-path> <branch> <from-branch> "<task>"
#>

param(
    [Parameter(Mandatory=$true, Position=0)] [string]$Worktree,
    [Parameter(Mandatory=$true, Position=1)] [string]$Branch,
    [Parameter(Mandatory=$true, Position=2)] [string]$FromBranch,
    [Parameter(Mandatory=$true, Position=3)] [string]$Task
)

function Fail($msg) {
    [Console]::Error.WriteLine("ERROR: $msg")
    exit 1
}

if (-not (Test-Path $Worktree -PathType Container)) {
    Fail "worktree directory not found: $Worktree"
}

$claudeFile   = Join-Path $Worktree "CLAUDE.md"
$worktwinFile = Join-Path $Worktree "WORKTWIN.md"
$beginMarker  = '<!-- BEGIN worktwin -->'
$endMarker    = '<!-- END worktwin -->'

$worktwinBody = @"
# worktwin parallel worker context

This worktree is bound to branch ``$Branch`` based on ``$FromBranch``.
Worktree path: ``$Worktree``

These rules apply for the whole session, every follow-up message,
and any new Claude Code session opened in this directory.

## Task

$Task

## DO

- Work only inside ``$Worktree``.
- Stay on branch ``$Branch`` for the entire session.
- Make atomic commits with messages like ``feat(scope): description``.
- After each meaningful unit of work, commit.
- Before you stop or hand control back to the user, commit every
  modification. The work is "done" only when ``git status --porcelain``
  is empty and your progress is reflected in commits ahead of
  ``$FromBranch``. The ship and finalize commands assume your branch
  is clean; never leave a dirty working tree behind.
- If the user asks you to continue or iterate, keep working on the
  same branch.

## DO NOT

- Run ``git checkout`` or ``git switch`` to a different branch.
- Modify files outside ``$Worktree``.
- Run ``git merge`` or ``git rebase`` unless the user explicitly asks.
- Delete the ``parallel/`` state files.
- Push to any branch other than ``$Branch``.

## Hard rule: do not commit worktwin context files

``CLAUDE.md`` in this worktree has been appended with a worktwin
reference block, and ``WORKTWIN.md`` is a worktwin-local file. Both
are local-only context and must NEVER be committed.

- If the user explicitly asks to commit either file, FIRST warn that
  ``CLAUDE.md`` references a local worktwin context file
  (``WORKTWIN.md``) that only exists in this worktree, and confirm
  the user really wants to commit the local override before
  proceeding.
- Otherwise, treat both files as untouchable from git's perspective.
"@

$tailBlock = @"
$beginMarker
This worktree is a worktwin parallel worker. The parallel-worker
rules, the bound branch, and the current task live in ``WORKTWIN.md``
at the worktree root. Those rules apply on top of everything above.

@WORKTWIN.md

Hard rule: do NOT commit changes to ``CLAUDE.md`` or ``WORKTWIN.md``.
If the user explicitly asks to commit either, warn first that
``CLAUDE.md`` contains a local worktwin reference block and
``WORKTWIN.md`` is a local-only context file.
$endMarker
"@

# Write WORKTWIN.md (full rules).
Set-Content -Path $worktwinFile -Value ($worktwinBody + "`n") -Encoding utf8 -NoNewline

# Update CLAUDE.md: preserve existing content, strip any old worktwin
# block, append the new tail at the bottom.
if (Test-Path $claudeFile) {
    $content = Get-Content $claudeFile -Raw
    if ($null -eq $content) { $content = '' }
    $pattern = "(?ms)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker) + "\r?\n?"
    $rest = [regex]::Replace($content, $pattern, '')
    $rest = $rest -replace '[\r\n\s]+$', ''
    if ([string]::IsNullOrWhiteSpace($rest)) {
        $output = $tailBlock + "`n"
    } else {
        $output = $rest + "`n`n" + $tailBlock + "`n"
    }
    Set-Content -Path $claudeFile -Value $output -Encoding utf8 -NoNewline
} else {
    Set-Content -Path $claudeFile -Value ($tailBlock + "`n") -Encoding utf8 -NoNewline
}

# Mark both files as "do not commit". Skip silently if not in a git repo.
function Run-Git {
    param([string[]]$Args)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath git -ArgumentList $Args -WorkingDirectory $Worktree `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    $stdout = (Get-Content $tmpOut -Raw)
    Remove-Item -Force $tmpOut, $tmpErr -ErrorAction SilentlyContinue
    if ($null -eq $stdout) { $stdout = '' }
    return [pscustomobject]@{ Code = $proc.ExitCode; Out = $stdout.Trim() }
}

$inRepo = Run-Git @('rev-parse', '--git-dir')
if ($inRepo.Code -ne 0) { exit 0 }

function Add-ToExclude {
    param([string]$Entry)
    $r = Run-Git @('rev-parse', '--git-path', 'info/exclude')
    if ($r.Code -ne 0 -or [string]::IsNullOrWhiteSpace($r.Out)) { return }
    $excludePath = $r.Out
    if (-not ([System.IO.Path]::IsPathRooted($excludePath))) {
        $excludePath = Join-Path $Worktree $excludePath
    }
    $excludeDir = Split-Path $excludePath -Parent
    if (-not (Test-Path $excludeDir)) {
        New-Item -ItemType Directory -Path $excludeDir -Force | Out-Null
    }
    if (Test-Path $excludePath) {
        $existing = Get-Content $excludePath -ErrorAction SilentlyContinue
        if ($existing -contains $Entry) { return }
        Add-Content -Path $excludePath -Value $Entry -Encoding utf8
    } else {
        Set-Content -Path $excludePath -Value ($Entry + "`n") -Encoding utf8 -NoNewline
    }
}

function Mark-NoCommit {
    param([string]$Rel)
    $check = Run-Git @('ls-files', '--error-unmatch', '--', $Rel)
    if ($check.Code -eq 0) {
        Run-Git @('update-index', '--skip-worktree', '--', $Rel) | Out-Null
    } else {
        Add-ToExclude "/$Rel"
    }
}

Mark-NoCommit 'CLAUDE.md'
Mark-NoCommit 'WORKTWIN.md'
