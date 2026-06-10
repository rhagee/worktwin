#Requires -Version 5.1

param(
    [string]$Mode = "global",
    [switch]$SkipDevDriveSetup
)

switch ($Mode) {
    "global" {
        $Target = Join-Path $env:USERPROFILE ".claude\skills"
    }
    "local" {
        $RepoRoot = & git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RepoRoot)) {
            Write-Host "ERROR: 'local' mode requires running inside a git repo"
            exit 1
        }
        $Target = Join-Path $RepoRoot ".claude\skills"
    }
    default {
        $Target = Join-Path $Mode ".claude\skills"
    }
}

$Src = Join-Path $PSScriptRoot "skills"
if (-not (Test-Path $Src)) {
    Write-Host "ERROR: skills/ directory not found at $Src"
    exit 1
}

if (-not (Test-Path $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

$Skills = @(
    "worktwin",
    "worktwin-ship",
    "worktwin-ship-all",
    "worktwin-finalize",
    "worktwin-merge-solver",
    "worktwin-status",
    "worktwin-clear",
    "worktwin-light-doctor",
    "worktwin-light-setup-windows",
    "worktwin-light-teardown-windows",
    "worktwin-help",
    "worktwin-update"
)

foreach ($Skill in $Skills) {
    $Dest = Join-Path $Target $Skill
    if (Test-Path $Dest) {
        Remove-Item -Path $Dest -Recurse -Force
    }
    Copy-Item -Path (Join-Path $Src $Skill) -Destination $Target -Recurse -Force
}

$BinSrc = Join-Path $PSScriptRoot "bin"
if (Test-Path $BinSrc) {
    $BinDst = Join-Path $Target "worktwin\bin"
    if (-not (Test-Path $BinDst)) { New-Item -ItemType Directory -Path $BinDst -Force | Out-Null }
    Copy-Item -Path (Join-Path $BinSrc "*") -Destination $BinDst -Recurse -Force
}

# Record where this clone lives so worktwin-update can find it later.
# Forward slashes so the path is consumable by both PowerShell and bash
# (Git Bash on Windows does not understand backslash paths in test -d).
# UTF-8 without BOM so bash does not read a stray zero-width character
# at the start of the path (Set-Content -Encoding utf8 on 5.1 adds a BOM).
$SourceFile = Join-Path $Target "worktwin\.source"
$NormalisedPath = $PSScriptRoot -replace '\\', '/'
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($SourceFile, $NormalisedPath, $Utf8NoBom)

Write-Host "worktwin installed to $Target"
Write-Host ""
Write-Host "Run /worktwin-help inside Claude Code to see every command."
Write-Host "Standalone CLI tools at $Target\worktwin\bin"

# Soft dependency note: the PowerShell flavour of every script (including
# worktwin-merge-solver.ps1) uses native ConvertTo-Json / ConvertFrom-Json
# and does not need jq. We only nudge here when the user does NOT have jq
# AND is likely to also run the bash flavour from Git Bash / WSL.
$jq = Get-Command jq -ErrorAction SilentlyContinue
$gitBash = (Test-Path "C:\Program Files\Git\bin\bash.exe") -or (Test-Path "C:\Program Files (x86)\Git\bin\bash.exe")
$wsl = Get-Command wsl -ErrorAction SilentlyContinue
if (-not $jq -and ($gitBash -or $wsl)) {
    Write-Host ""
    Write-Host "note: 'jq' was not found on PATH."
    Write-Host "      the PowerShell flavour of every worktwin script works without it."
    Write-Host "      jq is only needed if you also run the bash scripts (Git Bash / WSL)."
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "      install: scoop install jq"
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "      install: winget install jqlang.jq"
    } elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "      install: choco install jq"
    } else {
        Write-Host "      install with scoop / winget / choco, e.g.: scoop install jq"
    }
}

# -----------------------------------------------------------------------
# Guided Dev Drive setup (Windows only, only when there is no ReFS volume
# yet). Skip with -SkipDevDriveSetup or by answering "no" to the prompt.
# -----------------------------------------------------------------------
if ($SkipDevDriveSetup) {
    # silent
} elseif (-not [Environment]::OSVersion.Platform.ToString().StartsWith('Win')) {
    # not Windows, nothing to do
} else {
    $existingDev = $null
    try {
        $existingDev = Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $_.FileSystem -eq 'ReFS' -and $_.DriveLetter } |
            Select-Object -First 1
    } catch { }

    if ($existingDev) {
        Write-Host ""
        Write-Host "note: ReFS volume already present at $($existingDev.DriveLetter): - light mode is available." -ForegroundColor Green
    } elseif ([Console]::IsInputRedirected) {
        # non-interactive shell (CI, piped) - cannot prompt
        Write-Host ""
        Write-Host "note: no ReFS Dev Drive detected. Run /worktwin-light-setup-windows inside Claude Code (or .\bin\worktwin-light-setup-windows.ps1) to set up light mode." -ForegroundColor Gray
    } else {
        Write-Host ""
        Write-Host "==================================================================="  -ForegroundColor Cyan
        Write-Host "  worktwin light mode setup (optional)"                                -ForegroundColor Cyan
        Write-Host "==================================================================="  -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Light mode gives each parallel worker ~0 bytes of disk overhead via"  -ForegroundColor Gray
        Write-Host "filesystem copy-on-write. On Windows this needs a ReFS Dev Drive."    -ForegroundColor Gray
        Write-Host "If you skip, worktwin still works with standard worktrees (full file" -ForegroundColor Gray
        Write-Host "copies per worker)."                                                   -ForegroundColor Gray
        Write-Host ""
        $answer = Read-Host "Set up a Dev Drive now? (yes/no, default: no)"

        if ($answer -ne 'yes') {
            Write-Host ""
            Write-Host "Skipped. Set up later with:"  -ForegroundColor Gray
            Write-Host "  /worktwin-light-setup-windows   (inside Claude Code, guided)" -ForegroundColor Gray
            Write-Host "  $Target\worktwin\bin\worktwin-light-setup-windows.ps1" -ForegroundColor Gray
        } else {
            # Sorgenti possibili: dischi NTFS con almeno 50 GB liberi.
            $candidates = Get-PSDrive -PSProvider FileSystem |
                Where-Object { $_.Free -ge 50GB -and ($_.Name -match '^[A-Z]$') } |
                Sort-Object Free -Descending

            if ($candidates.Count -eq 0) {
                Write-Host ""
                Write-Host "no disk with at least 50 GB free was found. Free some space and re-run /worktwin-light-setup-windows later." -ForegroundColor Yellow
            } else {
                Write-Host ""
                Write-Host "Disks with at least 50 GB free (the VHDX file lives on one of these):" -ForegroundColor Gray
                foreach ($c in $candidates) {
                    $freeGB = [Math]::Round($c.Free / 1GB, 1)
                    Write-Host ("  {0}:   free {1} GB" -f $c.Name, $freeGB) -ForegroundColor Gray
                }
                $bestDisk = $candidates[0].Name
                $bestFreeGB = [Math]::Round($candidates[0].Free / 1GB, 1)
                Write-Host ""
                $diskChoice = Read-Host "Which disk should host the VHDX file? (letter, default: $bestDisk)"
                if ([string]::IsNullOrWhiteSpace($diskChoice)) { $diskChoice = $bestDisk }
                $diskChoice = $diskChoice.TrimEnd(':').ToUpper()

                if (-not ($candidates.Name -contains $diskChoice)) {
                    Write-Host "letter $diskChoice not in the candidate list. Aborting." -ForegroundColor Yellow
                } else {
                    $sourceFreeGB = [Math]::Round((Get-PSDrive -Name $diskChoice).Free / 1GB, 1)

                    # Suggerisci una lettera libera, preferendo le ultime dell'alfabeto.
                    $usedLetters = (Get-Volume -ErrorAction SilentlyContinue).DriveLetter | Where-Object { $_ }
                    $preferred = @('W','V','X','Y','Z','T','U','S','R','Q','P','O','N','M','L')
                    $defaultLetter = ($preferred | Where-Object { $usedLetters -notcontains $_ } | Select-Object -First 1)
                    if (-not $defaultLetter) { $defaultLetter = 'W' }

                    $letterChoice = Read-Host "Drive letter to mount the Dev Drive at? (default: $defaultLetter)"
                    if ([string]::IsNullOrWhiteSpace($letterChoice)) { $letterChoice = $defaultLetter }
                    $letterChoice = $letterChoice.TrimEnd(':').ToUpper()

                    # Default size cap: 100 GB se c'e spazio, altrimenti meta dello spazio libero, minimo 50.
                    $defaultSize = [Math]::Min(100, [int]($sourceFreeGB / 2))
                    if ($defaultSize -lt 50) { $defaultSize = 50 }
                    $sizeAnswer = Read-Host "VHDX size cap in GB? (dynamic, grows on use, default: $defaultSize, min: 50)"
                    if ([string]::IsNullOrWhiteSpace($sizeAnswer)) {
                        $sizeChoice = $defaultSize
                    } else {
                        $sizeChoice = [int]$sizeAnswer
                    }
                    if ($sizeChoice -lt 50) { $sizeChoice = 50 }

                    $vhdPath = "${diskChoice}:\worktwin-dev-drive.vhdx"

                    Write-Host ""
                    Write-Host "Plan:" -ForegroundColor Cyan
                    Write-Host "  VHDX file: $vhdPath ($sourceFreeGB GB free on ${diskChoice}:)" -ForegroundColor Gray
                    Write-Host "  Size cap:  $sizeChoice GB (dynamic, grows only when used)" -ForegroundColor Gray
                    Write-Host "  Mount as:  ${letterChoice}:" -ForegroundColor Gray
                    Write-Host "  + scheduled task: auto-mount at every system boot" -ForegroundColor Gray
                    Write-Host ""
                    $confirm = Read-Host "Proceed? Windows will ask for admin permission (yes/no)"

                    if ($confirm -ne 'yes') {
                        Write-Host "aborted. Run /worktwin-light-setup-windows inside Claude Code when ready." -ForegroundColor Yellow
                    } else {
                        $setupScript = Join-Path $Target "worktwin\bin\worktwin-light-setup-windows.ps1"
                        if (-not (Test-Path $setupScript)) {
                            Write-Host "ERROR: setup script missing at $setupScript" -ForegroundColor Red
                        } else {
                            Write-Host ""
                            Write-Host "Launching setup. Accept the UAC prompt when Windows asks." -ForegroundColor Cyan
                            & $setupScript -VhdPath $vhdPath -SizeGB $sizeChoice -DriveLetter $letterChoice
                        }
                    }
                }
            }
        }
    }
}
