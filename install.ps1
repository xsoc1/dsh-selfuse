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

.PARAMETER NoSystem
    Skip environment variables, scheduled tasks, services and health check.
    Useful for isolated DSH_HOME rehearsals.

.PARAMETER SkipSubmodules
    Do not run `git submodule update --init --recursive`.

.PARAMETER ProfileMode
    How to apply the web profile. Junction is deprecated and no longer supported;
    this parameter exists only for compatibility and must be 'Copy'.

.PARAMETER SkipPnpmInstall
    Do not run `pnpm install` in the web profile even when it is a fresh profile.

.EXAMPLE
    .\install.ps1 -DryRun
    .\install.ps1 -Force
    .\install.ps1 -Bootstrap
#>
param(
    [switch]$Bootstrap,
    [switch]$DryRun,
    [switch]$Force,
    [switch]$NoSystem,
    [switch]$SkipSubmodules,
    [switch]$SkipPnpmInstall,
    [ValidateSet('Copy')]
    [string]$ProfileMode = 'Copy'
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

function Install-MissingPrerequisite {
    param([string[]]$Commands)
    foreach ($cmd in $Commands) {
        switch ($cmd) {
            'git'   { $action = 'winget install --id Git.Git -e --silent' }
            'node'  { $action = 'winget install --id OpenJS.NodeJS.LTS -e --silent' }
            'pnpm'  { $action = 'corepack enable && npm install -g pnpm' }
            default { $action = "Please install $cmd manually" }
        }
        Write-Host "    $action"
        if (-not $DryRun) {
            switch ($cmd) {
                'git' {
                    if (Get-Command winget -ErrorAction SilentlyContinue) {
                        winget install --id Git.Git -e --silent --accept-package-agreements --accept-source-agreements
                    } else {
                        Write-Warning "    winget not available; install git manually"
                    }
                }
                'node' {
                    if (Get-Command winget -ErrorAction SilentlyContinue) {
                        winget install --id OpenJS.NodeJS.LTS -e --silent --accept-package-agreements --accept-source-agreements
                    } else {
                        Write-Warning "    winget not available; install node manually"
                    }
                }
                'pnpm' {
                    corepack enable
                    npm install -g pnpm
                }
            }
        }
    }
}

function Set-UserEnvironmentVariable {
    param([string]$Name, [string]$Value)
    $current = [Environment]::GetEnvironmentVariable($Name, 'User')
    if ($current -and $current -ne $Value -and -not $Force) {
        Write-Host "    skip $Name (already '$current'); use -Force to override"
        return
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Write-Host "    set $Name=$Value"
}

Write-Host ""
Write-Host "dsh-local installer" -ForegroundColor Green
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
        Write-Step "Bootstrap: installing missing prerequisites"
        Install-MissingPrerequisite -Commands $missing
    } else {
        Write-Warning "Install them manually or run with -Bootstrap."
    }
} else {
    Write-Step "Prerequisites OK: git/node/pnpm"
}

# --- 1. Submodules ----------------------------------------------------------
if (Test-Path (Join-Path $RepoRoot ".gitmodules")) {
    $harnessSub = Join-Path $RepoRoot "vendor\deepseek-harness"
    if ($SkipSubmodules) {
        Write-Step "Skip submodule update (-SkipSubmodules)"
        if (-not (Test-Path (Join-Path $harnessSub "package.json"))) {
            Write-Warning "vendor/deepseek-harness not populated; DSH_ROOT will fall back to F:\tools\deepseek-harness on this machine"
        }
    } else {
        Invoke-Step "Update git submodules" {
            git -C $RepoRoot submodule update --init --recursive
        }
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
# Agent presets must be real directories, never junctions: dsh scans them with
# Dirent.isDirectory(), which reports false for a Windows junction, so a
# junction preset disappears from the roster and its WSL variant is never
# generated. Copy instead of link.
$presetSrc = Join-Path $RepoRoot "config/agent-presets"
$presetDst = Join-Path $DshHome ".agent-presets"
if (Test-Path $presetSrc) {
    Invoke-Step "Sync agent-presets -> $presetDst" {
        New-Item -ItemType Directory -Force -Path $presetDst | Out-Null
        Get-ChildItem $presetSrc -Directory | ForEach-Object {
            $target = Join-Path $presetDst $_.Name
            if (Test-Path $target) {
                $item = Get-Item $target -Force
                if ($item.LinkType -eq 'Junction') {
                    # Remove only the junction link; the target tree stays.
                    [System.IO.Directory]::Delete($target)
                    Write-Host "    removed junction: $target"
                } elseif ($Force) {
                    $backup = "$target.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                    Rename-Item $target $backup
                    Write-Host "    backup: $backup"
                } else {
                    Write-Warning "    $target exists; use -Force to replace"
                    return
                }
            }
            if (-not (Test-Path $target)) {
                Copy-Item -Recurse $_.FullName $target
                Write-Host "    copy: $target"
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
    Invoke-Step "Sync web profile via Copy -> $profileDst" {
        New-Item -ItemType Directory -Force -Path $profileDst | Out-Null
        # On a fresh profile (no package.json), generate one with repo-root links.
        $pkgDst = Join-Path $profileDst "package.json"
        if (-not (Test-Path $pkgDst)) {
            $template = Join-Path $profileSrc "package.json.template"
            if (Test-Path $template) {
                $repoRootFwd = $RepoRoot -replace '\\','/'
                $content = Get-Content -Raw $template
                $content = $content.Replace('__REPO_ROOT__', $repoRootFwd)
                $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
                [System.IO.File]::WriteAllText($pkgDst, $content, $utf8NoBom)
                Write-Host "    generated package.json (repo-root links)"
            }
        }
        # Copy mode intentionally does NOT overwrite an existing package.json/pnpm-lock.yaml:
        # those encode link paths and would break an existing profile's node_modules.
        foreach ($file in @('cordis.patch.yml', 'pnpm-workspace.yaml')) {
            $srcFile = Join-Path $profileSrc $file
            $dstFile = Join-Path $profileDst $file
            if (Test-Path $srcFile) {
                if (Test-Path $dstFile) {
                    $backup = "$dstFile.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                    Copy-Item $dstFile $backup -Force
                    Write-Host "    backup: $backup"
                }
                Copy-Item $srcFile $dstFile -Force
                Write-Host "    copy: $file"
            }
        }
        Write-Host "    note: existing package.json/pnpm-lock.yaml not overwritten; new profile gets generated package.json; node_modules kept in $profileDst"
        $nodeModules = Join-Path $profileDst "node_modules"
        if (-not $SkipPnpmInstall -and -not (Test-Path $nodeModules)) {
            Write-Host "    running pnpm install in $profileDst ..."
            Push-Location $profileDst
            try {
                pnpm install --no-frozen-lockfile
            } finally {
                Pop-Location
            }
        }
        # Prune unused dsh-web-ui-all sub-plugins after profile sync/install.
        & (Join-Path $RepoRoot "scripts\prune-web-ui.ps1") -ProfilePath $profileDst -DryRun:$DryRun
    }
} else {
    Write-Warning "config/profiles/web not found; skip"
}

# --- 5. skills --------------------------------------------------------------
$skillsRoot = Join-Path $DshHome "skills"
$skillSources = @(
    @{ Name = "mattpocock"; Source = Join-Path $RepoRoot "skills/mattpocock-skills/skills" },
    @{ Name = "math-research"; Source = Join-Path $RepoRoot "skills/math-research-dsh/skills" },
    @{ Name = "obsidian"; Source = Join-Path $RepoRoot "skills/obsidian-skills/skills" }
)
foreach ($group in $skillSources) {
    if (Test-Path $group.Source) {
        Invoke-Step "Copy skills from $($group.Name)" {
            New-Item -ItemType Directory -Force -Path $skillsRoot | Out-Null
            Get-ChildItem $group.Source -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName "SKILL.md") } | ForEach-Object {
                $skill = $_.Name
                $src = $_.FullName
                $dst = Join-Path $skillsRoot $skill
                if (Test-Path $dst) {
                    $item = Get-Item $dst -Force
                    if ($item.LinkType) {
                        # Remove only the junction/symlink; the target tree stays.
                        if ($item.PSIsContainer) {
                            [System.IO.Directory]::Delete($dst)
                        } else {
                            Remove-Item $dst -Force
                        }
                        Write-Host "    removed link: $dst"
                    } elseif ($Force) {
                        $backup = "$dst.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                        Rename-Item $dst $backup
                        Write-Host "    backup: $backup"
                    } else {
                        Write-Warning "    $dst exists; use -Force to replace"
                        return
                    }
                }
                if (-not (Test-Path $dst)) {
                    Copy-Item -Recurse $src $dst
                    Write-Host "    copy: $dst"
                }
            }
        }
    } else {
        Write-Step "Skill group $($group.Name) not vendored yet; skip"
    }
}

# --- 6. environment variables ------------------------------------------------
if (-not $NoSystem) {
    Invoke-Step "Set user environment variables" {
        $dshRoot = Join-Path $RepoRoot "vendor\deepseek-harness"
        if (-not (Test-Path $dshRoot)) {
            if (Test-Path "F:\tools\deepseek-harness") { $dshRoot = "F:\tools\deepseek-harness" }
        }
        Set-UserEnvironmentVariable "DSH_ROOT" $dshRoot
        Write-Host "    note: OPENCODE_GO_API_KEY etc. are read from system/user secrets; not written by installer"
    }
} else {
    Write-Step "Skip environment variables (-NoSystem)"
}

# --- 7. scheduled tasks & services -------------------------------------------
if (-not $NoSystem) {
    Invoke-Step "Register watchdog scheduled tasks" {
        $watchdogVbs = Join-Path $RepoRoot "scripts\dsh-watchdog.vbs"
        $ensureVbs = Join-Path $RepoRoot "scripts\ensure-dsh-watchdog.vbs"
        schtasks.exe /Create /TN "dsh-watchdog" /TR "wscript.exe `"$watchdogVbs`"" /SC ONLOGON /RL HIGHEST /F | Out-Null
        schtasks.exe /Create /TN "dsh-watchdog-ensure" /TR "wscript.exe `"$ensureVbs`"" /SC MINUTE /MO 5 /RL HIGHEST /F | Out-Null
        Write-Host "    registered dsh-watchdog / dsh-watchdog-ensure"
    }

} else {
    Write-Step "Skip scheduled tasks / services (-NoSystem)"
}

# --- 8. health check ---------------------------------------------------------
if (-not $NoSystem) {
    Invoke-Step "Health check" {
        $checks = @(
            @{ Name = "dsh web";   Url = "http://127.0.0.1:3080" }
        )
        foreach ($c in $checks) {
            try {
                $r = Invoke-WebRequest -Uri $c.Url -UseBasicParsing -TimeoutSec 3
                Write-Host "    $($c.Name): OK ($($r.StatusCode))"
            } catch {
                Write-Warning "    $($c.Name): unreachable"
            }
        }
    }
} else {
    Write-Step "Skip health check (-NoSystem)"
}

Write-Host ""
Write-Host "Done. Next steps:" -ForegroundColor Green
Write-Host "  1. Review docs/PLAN.md"
Write-Host "  2. Run .\install.ps1 -DryRun to preview"
Write-Host "  3. After migration, run .\install.ps1 -Force to apply"
