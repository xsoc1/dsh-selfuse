<#
.SYNOPSIS
    Keep unused @linxin666/dsh-web-ui-all sub-plugins out of the loader patch.

.DESCRIPTION
    NOTE: the real slimming is done by the local file: dependency
    F:\tools\dsh-local\plugins\dsh-web-ui-all-slim (a 0.2.7 copy whose
    package.json no longer depends on the removed sub-plugins). This script is
    only a defensive guard for older/upgraded installs:

    Strips insert rows for selected sub-plugins (pet, describe-image,
    aionui-panel, liangshen, skill-explorer, desktop-launcher,
    plugin-manager) from the installed dsh-web-ui-all aggregate:

      1. strips their insert rows from
         node_modules\@linxin666\dsh-web-ui-all\cordis.patch.yml
      2. leaves their node_modules\@linxin666\ package directories in place

    Do NOT delete the package directories: dsh 0.1.1 resolves every
    client-module bundle by dependency path, so a missing package turns into
    "bundle script ... failed to load" even when the loader patch has no row
    for it. Disabling via the patch layer is the supported way to turn them
    off. Run this after every `pnpm install` or dsh-web-ui-all upgrade so the
    selected loader rows do not come back.

.PARAMETER ProfilePath
    Path to the dsh web profile. Defaults to %USERPROFILE%\.dsh\profiles\web.

.PARAMETER DryRun
    Show what would be removed without changing files.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\prune-web-ui.ps1
#>
param(
    [string]$ProfilePath = (Join-Path $env:USERPROFILE '.dsh\profiles\web'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RemoveNamesPattern = 'dsh-pet|dsh-tool-describe-image|dsh-client-ui-aionui-panel|dsh-liangshen|dsh-client-ui-skill-explorer|dsh-desktop-launcher|dsh-client-ui-plugin-manager'

Write-Host "Prune dsh-web-ui-all in: $ProfilePath"
if ($DryRun) { Write-Host 'Mode: DRY RUN' }

$aggDir = Join-Path $ProfilePath 'node_modules\@linxin666\dsh-web-ui-all'
$aggPatch = Join-Path $aggDir 'cordis.patch.yml'
if (Test-Path $aggPatch) {
    $content = Get-Content -Raw -Path $aggPatch
    $newContent = [regex]::Replace(
        $content,
        "(?m)^# from [^\r\n]*\r?\n- insert:\r?\n    - id: [^\r\n]+\r?\n      name: '[^']*($RemoveNamesPattern)[^']*'\r?\n\r?\n?",
        ''
    )
    if ($newContent -ne $content) {
        if ($DryRun) {
            Write-Host "  [dry-run] would strip remove rows from $aggPatch"
        } else {
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($aggPatch, $newContent, $utf8NoBom)
            Write-Host "  stripped remove rows from $aggPatch"
        }
    } else {
        Write-Host "  no remove rows found in $aggPatch"
    }
} else {
    Write-Host "  aggregate patch not found: $aggPatch"
}

$scopeDir = Join-Path $ProfilePath 'node_modules\@linxin666'
Write-Host "  package directories kept: $scopeDir (required by dsh client-modules)"

Write-Host 'prune-web-ui done'
