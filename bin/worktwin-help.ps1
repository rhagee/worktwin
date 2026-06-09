#Requires -Version 5.1
<#
worktwin-help.ps1 - print every installed worktwin command, with arguments
and a short description, by reading the installed SKILL.md frontmatter.
#>

$skillsDir = $null

# Self-locate: script may live at <skills>\worktwin\bin\.
$scriptDir = $PSScriptRoot
if ($scriptDir) {
    $candidate = Resolve-Path (Join-Path $scriptDir "..\..") -ErrorAction SilentlyContinue
    if ($candidate -and (Test-Path (Join-Path $candidate.Path "worktwin\SKILL.md"))) {
        $skillsDir = $candidate.Path
    }
}

if (-not $skillsDir) {
    $candidate = Join-Path $env:USERPROFILE ".claude\skills"
    if (Test-Path (Join-Path $candidate "worktwin\SKILL.md")) { $skillsDir = $candidate }
}

if (-not $skillsDir) {
    Write-Host "worktwin does not seem to be installed on this machine."
    Write-Host "see https://github.com/rhagee/worktwin"
    exit 0
}

# When the output is captured (typical for the worktwin-help skill), wrap
# the body in a code fence so the markdown renderer preserves angle
# brackets. When called from a real terminal, the fence is omitted.
$useFence = [Console]::IsOutputRedirected
if ($useFence) { Write-Host '```' }

$order = @(
    "worktwin",
    "worktwin-status",
    "worktwin-ship",
    "worktwin-ship-all",
    "worktwin-finalize",
    "worktwin-clear",
    "worktwin-update",
    "worktwin-help"
)

function Emit-Skill($dir) {
    $file = Join-Path $dir "SKILL.md"
    if (-not (Test-Path $file)) { return }
    $name = Split-Path -Leaf $dir
    $content = Get-Content $file -Raw
    $hint = ""
    $desc = ""
    if ($content -match '(?m)^argument-hint:\s*(.+)$') {
        $raw = $matches[1].Trim()
        if ($raw -match '^"(.*)"$') { $hint = $matches[1] } else { $hint = $raw }
    }
    if ($content -match '(?m)^description:\s*(.+)$') {
        $desc = $matches[1].Trim()
    }
    $short = $desc -replace '\.\s+[A-Z].*$', '.'
    if ($hint) {
        Write-Host "/$name $hint"
    } else {
        Write-Host "/$name"
    }
    Write-Host "  $short"
    Write-Host ""
}

foreach ($name in $order) {
    $dir = Join-Path $skillsDir $name
    if (Test-Path $dir) { Emit-Skill $dir }
}

Get-ChildItem -Path $skillsDir -Directory -Filter "worktwin*" | ForEach-Object {
    if ($order -notcontains $_.Name) {
        Emit-Skill $_.FullName
    }
}

Write-Host "docs: https://github.com/rhagee/worktwin"

if ($useFence) { Write-Host '```' }
