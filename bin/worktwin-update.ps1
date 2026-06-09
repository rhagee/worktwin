#Requires -Version 5.1
<#
worktwin-update.ps1 - find the cloned worktwin repo via .source and
run update.ps1 from there. Pluggable: works as a CLI tool and from
the worktwin-update skill.
#>

$sourceFile = $null
$scriptDir = $PSScriptRoot
if ($scriptDir) {
    $candidate = Join-Path $scriptDir "..\.source"
    if (Test-Path $candidate) { $sourceFile = (Resolve-Path $candidate).Path }
}
if (-not $sourceFile) {
    $candidate = Join-Path $env:USERPROFILE ".claude\skills\worktwin\.source"
    if (Test-Path $candidate) { $sourceFile = $candidate }
}

if (-not $sourceFile) {
    Write-Host "worktwin source path is not recorded (no .source file)."
    Write-Host "Did you install via install.sh or install.ps1 from a cloned worktwin repo?"
    exit 0
}

$sourceRoot = (Get-Content -Path $sourceFile -Raw).Trim() -replace '\\', '/'
# Strip a UTF-8 BOM if Get-Content surfaced one
if ($sourceRoot.Length -gt 0 -and [int][char]$sourceRoot[0] -eq 0xFEFF) {
    $sourceRoot = $sourceRoot.Substring(1)
}

if (-not (Test-Path $sourceRoot)) {
    Write-Host "Recorded source path no longer exists: $sourceRoot"
    Write-Host "Re-run install.sh or install.ps1 from the current path of your cloned worktwin repo."
    exit 0
}

$updateScript = Join-Path $sourceRoot "update.ps1"
if (-not (Test-Path $updateScript)) {
    Write-Host "update.ps1 not found at $sourceRoot. Pull the worktwin repo first or re-run install."
    exit 0
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $updateScript
