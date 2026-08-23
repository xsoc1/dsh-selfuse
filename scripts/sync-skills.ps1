# Sync vendored skills from the live source repos into dsh-local/skills.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/sync-skills.ps1
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$targets = @(
    @{ Name = 'mattpocock-skills'; Source = 'F:\tools\mattpocock-skills'; Dest = Join-Path $RepoRoot 'skills\mattpocock-skills' },
    @{ Name = 'math-research-dsh'; Source = 'C:\Users\HuangZY\.dsh\math-research-dsh'; Dest = Join-Path $RepoRoot 'skills\math-research-dsh' }
    @{ Name = 'obsidian-skills'; Source = '\\wsl.localhost\Ubuntu\home\huangzy\tools\obsidian-skills'; Dest = Join-Path $RepoRoot 'skills\obsidian-skills' }
)

foreach ($t in $targets) {
    if (-not (Test-Path $t.Source)) {
        Write-Warning "source not found: $($t.Source); skip $($t.Name)"
        continue
    }
    Write-Host "Syncing $($t.Name) ..."
    if (Test-Path $t.Dest) {
        Remove-Item -Recurse -Force $t.Dest
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $t.Dest) | Out-Null
    Copy-Item -Recurse $t.Source $t.Dest
    # Remove VCS metadata so the vendored copy stays a plain tree.
    foreach ($sub in @('.git', 'node_modules')) {
        $p = Join-Path $t.Dest $sub
        if (Test-Path $p) {
            Remove-Item -Recurse -Force $p
        }
    }
    Write-Host "  -> $($t.Dest)"
}

Write-Host 'skills sync complete'
