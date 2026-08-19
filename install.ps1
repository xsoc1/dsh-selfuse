<#
.SYNOPSIS
    dsh-local one-click install / configure / repair.

.DESCRIPTION
    Syncs this repository's canonical config, skills, plugins and services into
    the local DSH environment (~/.dsh) and the runtime directories.

    Current status: SKELETON. Some steps are implemented, some are placeholders.

.PARAMETER Bootstrap
    Full deployment on a new machine (install prerequisites too).

.PARAMETER DryRun
    Print actions without changing anything.

.PARAMETER Force
    Replace existing non-junction targets (backup first).

.EXAMPLE
    .\install.ps1 -DryRun
    .\install.ps1 -Force
    .\install.ps1 -Bootstrap
#>
param(
    [switch]$Bootstrap,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME ".dsh" }

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Step $Name
    if ($DryRun) {
        Write-Host "    [dry-run] would execute: $($Action.ToString())" -ForegroundColor DarkGray
        return
    }
    & $Action
}

function Test-CommandAvailable([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Host ""
Write-Host "dsh-local installer (skeleton)" -ForegroundColor Green
Write-Host "RepoRoot: $RepoRoot"
Write-Host "DSH_HOME: $DshHome"
if ($DryRun) { Write-Host "Mode: DRY RUN" -ForegroundColor Yellow }
if ($Bootstrap) { Write-Host "Mode: BOOTSTRAP" -ForegroundColor Yellow }
Write-Host ""

# --- 0. Prerequisites -------------------------------------------------------
$missing = @()
foreach ($cmd in @("git", "node", "pnpm")) {
    if (-not (Test-CommandAvailable $cmd)) { $missing += $cmd }
}
if ($missing.Count -gt 0) {
    Write-Warning "Missing commands: $($missing -join ', ')"
    if ($Bootstrap) {
        Write-Step "Bootstrap would install prerequisites (TODO: implement winget/choco installer)"
    } else {
        Write-Warning "Install them manually or run with -Bootstrap."
    }
} else {
    Write-Step "Prerequisites OK: git/node/pnpm"
}

# --- 1. Submodules ----------------------------------------------------------
if (Test-Path (Join-Path $RepoRoot ".gitmodules")) {
    Invoke-Step "Update git submodules" {
        git -C $RepoRoot submodule update --init --recursive
    }
} else {
    Write-Step "No .gitmodules yet; submodule setup is a Phase 2 task"
}

# --- 2. settings.yaml -------------------------------------------------------
$settingsSrc = Join-Path $RepoRoot "config/settings.yaml"
$settingsDst = Join-Path $DshHome "settings.yaml"
if (Test-Path $settingsSrc) {
    Invoke-Step "Sync settings.yaml -> $settingsDst" {
        New-Item -ItemType Directory -Force -Path $DshHome | Out-Null
        if (Test-Path $settingsDst) {
            $backup = "$settingsDst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Copy-Item $settingsDst $backup -Force
            Write-Host "    backup: $backup"
        }
        Copy-Item $settingsSrc $settingsDst -Force
    }
} else {
    Write-Warning "config/settings.yaml not found; skip"
}

# --- 3. agent-presets -------------------------------------------------------
$presetSrc = Join-Path $RepoRoot "config/agent-presets"
$presetDst = Join-Path $DshHome ".agent-presets"
if (Test-Path $presetSrc) {
    Invoke-Step "Sync agent-presets -> $presetDst" {
        New-Item -ItemType Directory -Force -Path $presetDst | Out-Null
        Get-ChildItem $presetSrc -Directory | ForEach-Object {
            $target = Join-Path $presetDst $_.Name
            if (Test-Path $target) {
                $item = Get-Item $target -Force
                if (-not $item.LinkType) {
                    if ($Force) {
                        $backup = "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                        Rename-Item $target $backup
                        Write-Host "    backup: $backup"
                    } else {
                        Write-Warning "    $target exists and is not a junction; use -Force to replace"
                        return
                    }
                }
            }
            if (-not (Test-Path $target)) {
                New-Item -ItemType Junction -Path $target -Target $_.FullName | Out-Null
                Write-Host "    junction: $target -> $($_.FullName)"
            }
        }
    }
} else {
    Write-Warning "config/agent-presets not found; skip"
}

# --- 4. web profile ---------------------------------------------------------
$profileSrc = Join-Path $RepoRoot "config/profiles/web"
$profileDst = Join-Path $DshHome "profiles/web"
if (Test-Path $profileSrc) {
    Invoke-Step "Sync web profile -> $profileDst" {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profileDst) | Out-Null
        if (Test-Path $profileDst) {
            $item = Get-Item $profileDst -Force
            if (-not $item.LinkType) {
                if ($Force) {
                    $backup = "$profileDst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                    Rename-Item $profileDst $backup
                    Write-Host "    backup: $backup"
                } else {
                    Write-Warning "    $profileDst exists and is not a junction; use -Force to replace"
                    return
                }
            }
        }
        if (-not (Test-Path $profileDst)) {
            New-Item -ItemType Junction -Path $profileDst -Target $profileSrc | Out-Null
            Write-Host "    junction: $profileDst -> $profileSrc"
        }
        # TODO: run pnpm install inside profile after junction is in place
        Write-Host "    TODO: run 'pnpm install' in $profileDst"
    }
} else {
    Write-Warning "config/profiles/web not found; skip"
}

# --- 5. skills --------------------------------------------------------------
$skillsRoot = Join-Path $DshHome "skills"
$skillSources = @(
    @{ Name = "mattpocock"; Source = Join-Path $RepoRoot "skills/mattpocock-skills/skills" },
    @{ Name = "math-research"; Source = Join-Path $RepoRoot "skills/math-research-dsh/skills" }
)
foreach ($group in $skillSources) {
    if (Test-Path $group.Source) {
        Invoke-Step "Link skills from $($group.Name)" {
            New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null
            Get-ChildItem $group.Source -Directory | ForEach-Object {
                $skill = $_.Name
                $src = $_.FullName
                $dst = Join-Path $skillsRoot $skill
                if (-not (Test-Path (Join-Path $src "SKILL.md"))) { return }
                if (Test-Path $dst) {
                    $item = Get-Item $dst -Force
                    if ($item.LinkType) { return }
                    if ($Force) {
                        $backup = "$dst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                        Rename-Item $dst $backup
                        Write-Host "    backup: $backup"
                    } else {
                        Write-Warning "    $dst exists and is not a junction; use -Force to replace"
                        return
                    }
                }
                if (-not (Test-Path $dst)) {
                    New-Item -ItemType Junction -Path $dst -Target $src | Out-Null
                    Write-Host "    junction: $dst -> $src"
                }
            }
        }
    } else {
        Write-Step "Skill group $($group.Name) not vendored yet; skip"
    }
}

# --- 6. environment variables (TODO) ----------------------------------------
Invoke-Step "Set environment variables (DSH_ROOT / OLLAMA_MODELS / HF_HOME)" {
    # TODO: setx / [Environment]::SetEnvironmentVariable for user scope
    Write-Host "    TODO: DSH_ROOT=$RepoRoot\vendor\deepseek-harness"
    Write-Host "    TODO: OLLAMA_MODELS=... / HF_HOME=..."
}

# --- 7. scheduled tasks & services (TODO) -----------------------------------
Invoke-Step "Register watchdog scheduled tasks / start services" {
    # TODO: use scripts/ensure-dsh-watchdog.ps1 and dsh-control.ps1
    Write-Host "    TODO: scheduled tasks and service startup"
}

# --- 8. health check (TODO) -------------------------------------------------
Invoke-Step "Health check" {
    # TODO: probe 3080 / 11810 / 17821
    Write-Host "    TODO: check dsh web, Ollama, image-gen"
}

Write-Host ""
Write-Host "Done (skeleton). Next steps:" -ForegroundColor Green
Write-Host "  1. Review docs/PLAN.md"
Write-Host "  2. Run .\install.ps1 -DryRun to preview"
Write-Host "  3. After migration, run .\install.ps1 -Force to apply"
