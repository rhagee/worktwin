#Requires -Version 5.1
<#
worktwin-light-base.ps1 - manage the mapping from main repo paths to
light-mode base paths on Windows. Mirrors the bash version's contract.

Usage:
  .\worktwin-light-base.ps1 list
  .\worktwin-light-base.ps1 get <main-path>
  .\worktwin-light-base.ps1 set <main-path> <base-path>
  .\worktwin-light-base.ps1 remove <main-path>
  .\worktwin-light-base.ps1 path
#>

param(
    [Parameter(Position=0)] [string]$Command,
    [Parameter(ValueFromRemainingArguments=$true)] [string[]]$Rest
)

$configFile = $env:WORKTWIN_LIGHT_BASES_FILE
if (-not $configFile) {
    $configFile = Join-Path $env:USERPROFILE ".claude\skills\worktwin\.light-bases.json"
}

function Ensure-Config {
    $dir = Split-Path -Parent $configFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (-not (Test-Path $configFile)) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($configFile, '{"version":1,"bases":{}}', $utf8NoBom)
    }
}

function Read-Config {
    Ensure-Config
    Get-Content -Path $configFile -Raw | ConvertFrom-Json
}

function Write-Config($obj) {
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $json = $obj | ConvertTo-Json -Depth 10 -Compress
    [System.IO.File]::WriteAllText($configFile, $json, $utf8NoBom)
}

function To-Hashtable($obj) {
    # Convert a PSCustomObject (from ConvertFrom-Json) back to a hashtable
    # so we can add/remove keys cleanly.
    $h = @{}
    if ($null -eq $obj) { return $h }
    foreach ($prop in $obj.PSObject.Properties) {
        $h[$prop.Name] = $prop.Value
    }
    return $h
}

switch ($Command) {
    "list" {
        $cfg = Read-Config
        foreach ($prop in $cfg.bases.PSObject.Properties) {
            $entry = [ordered]@{
                main_repo     = $prop.Name
                light_base    = $prop.Value.light_base
                created_at    = $prop.Value.created_at
                source_branch = $prop.Value.source_branch
            }
            $entry | ConvertTo-Json -Compress
        }
        exit 0
    }

    "get" {
        $main = $Rest[0]
        if (-not $main) {
            [Console]::Error.WriteLine("usage: worktwin-light-base get <main-path>")
            exit 2
        }
        $cfg = Read-Config
        $entry = $cfg.bases.$main
        if (-not $entry) { exit 1 }
        $out = [ordered]@{ main_repo = $main }
        foreach ($prop in $entry.PSObject.Properties) {
            $out[$prop.Name] = $prop.Value
        }
        $out | ConvertTo-Json -Compress
        exit 0
    }

    "set" {
        $main = $Rest[0]
        $base = $Rest[1]
        if (-not $main -or -not $base) {
            [Console]::Error.WriteLine("usage: worktwin-light-base set <main-path> <base-path>")
            exit 2
        }
        if (-not (Test-Path $base -PathType Container)) {
            [Console]::Error.WriteLine("ERROR: base path does not exist: $base")
            exit 1
        }
        try { $main = (Resolve-Path $main -ErrorAction Stop).Path } catch {}
        $base = (Resolve-Path $base).Path

        $cfg = Read-Config
        $bases = To-Hashtable $cfg.bases
        $now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        $existing = $null
        if ($bases.ContainsKey($main)) { $existing = To-Hashtable $bases[$main] }
        $entry = @{
            light_base = $base
            updated_at = $now
            created_at = if ($existing -and $existing.created_at) { $existing.created_at } else { $now }
        }
        if ($existing -and $existing.source_branch) { $entry.source_branch = $existing.source_branch }
        $bases[$main] = $entry

        $newCfg = @{ version = 1; bases = $bases }
        Write-Config $newCfg
        Write-Host "set: $main -> $base"
        exit 0
    }

    "remove" {
        $main = $Rest[0]
        if (-not $main) {
            [Console]::Error.WriteLine("usage: worktwin-light-base remove <main-path>")
            exit 2
        }
        $cfg = Read-Config
        $bases = To-Hashtable $cfg.bases
        if (-not $bases.ContainsKey($main)) {
            [Console]::Error.WriteLine("no mapping was set for $main")
            exit 1
        }
        $bases.Remove($main) | Out-Null
        $newCfg = @{ version = 1; bases = $bases }
        Write-Config $newCfg
        Write-Host "removed: $main"
        exit 0
    }

    "path" {
        Write-Output $configFile
        exit 0
    }

    default {
        Write-Host "worktwin-light-base <list|get|set|remove|path>"
        Write-Host ""
        Write-Host "list                              every mapping as NDJSON"
        Write-Host "get <main-path>                   one mapping or exit 1"
        Write-Host "set <main-path> <base-path>       add or update a mapping"
        Write-Host "remove <main-path>                drop a mapping"
        Write-Host "path                              print the config file path"
        if (-not $Command) { exit 0 } else { exit 2 }
    }
}
