#Requires -Version 5.1
<#
worktwin-claude-md.ps1 - write or update the worktwin rules block in a
worktree's CLAUDE.md. Idempotent. Preserves anything outside the block.

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

$claudeFile  = Join-Path $Worktree "CLAUDE.md"
$beginMarker = '<!-- BEGIN worktwin -->'
$endMarker   = '<!-- END worktwin -->'

$block = @"
$beginMarker
# worktwin parallel worker rules

This session is bound to branch ``$Branch`` in worktree ``$Worktree``,
based on ``$FromBranch``. These rules apply for the whole session, every
follow-up message, and any new Claude Code session opened in this directory.

DO
- Work only inside ``$Worktree``.
- Stay on branch ``$Branch`` for the entire session.
- Make atomic commits with messages like ``feat(scope): description``.
- After each meaningful unit of work, commit.
- If the user asks you to continue or iterate, keep working on the same branch.

DO NOT
- Run ``git checkout`` or ``git switch`` to a different branch.
- Modify files outside ``$Worktree``.
- Run ``git merge`` or ``git rebase`` unless the user explicitly asks.
- Delete the ``parallel/`` state files.
- Push to any branch other than ``$Branch``.

Task: $Task
$endMarker
"@

if (Test-Path $claudeFile) {
    $content = Get-Content $claudeFile -Raw
    $pattern = "(?ms)" + [regex]::Escape($beginMarker) + ".*?" + [regex]::Escape($endMarker) + "\r?\n?"
    if ($content -match $pattern) {
        $rest = ($content -replace $pattern, '').TrimStart()
    } else {
        $rest = $content.TrimStart()
    }
    if ([string]::IsNullOrWhiteSpace($rest)) {
        $output = $block + "`n"
    } else {
        $output = $block + "`n`n" + $rest
    }
    Set-Content -Path $claudeFile -Value $output -Encoding utf8 -NoNewline
} else {
    Set-Content -Path $claudeFile -Value ($block + "`n") -Encoding utf8 -NoNewline
}
