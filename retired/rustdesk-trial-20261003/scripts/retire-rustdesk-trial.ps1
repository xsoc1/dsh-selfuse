param([switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TrialRoot = 'F:\Apps\RustDeskTrial'
$ArchiveParent = 'F:\tools\dsh-retired-20261003'
$StatusPath = 'F:\Apps\DeepSeekHarnessRemote\rustdesk-retirement.json'
$TrialScript = Join-Path $PSScriptRoot 'rustdesk-trial.ps1'
$Utf8 = New-Object Text.UTF8Encoding($false)
$Result = [ordered]@{ StartedAt = [DateTimeOffset]::Now.ToString('o'); Completed = $false; Archive = $null }
try {
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run from normal elevated Windows PowerShell.' }
    $Root = (Resolve-Path -LiteralPath $TrialRoot).Path
    if ($Root -ne $TrialRoot -or [IO.Path]::GetFullPath($Root) -ne $TrialRoot) { throw 'Unexpected trial root.' }
    $State = Get-Content -LiteralPath (Join-Path $TrialRoot 'trial-state.json') -Raw | ConvertFrom-Json
    if ($State.OwnerSid -ne $Identity.User.Value -or -not $State.NativeRootCreated -or $State.ConfigExistedBefore) { throw 'Trial ownership mismatch.' }
    if (@(Get-Process -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0 -or
        @(Get-Service -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'RustDesk must be normally exited and no service installed.' }
    $Archive = Join-Path $ArchiveParent ('rustdesk-trial-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    if (Test-Path -LiteralPath $Archive) { throw 'Archive already exists.' }
    if (-not [IO.Path]::GetFullPath($Archive).StartsWith($ArchiveParent + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive target.' }
    if (-not $Apply) { Write-Output 'Validated trial ownership; use -Apply for precise, recoverable retirement.'; exit 0 }
    # Child scripts intentionally run in this native elevated context, not Codex AppData virtualization.
    & $TrialScript -Action RemoveFirewall
    if ($LASTEXITCODE -ne 0) { throw 'Firewall cleanup failed.' }
    & $TrialScript -Action ArchiveConfig
    if ($LASTEXITCODE -ne 0) { throw 'Native config archival failed.' }
    if (Test-Path -LiteralPath $State.ConfigRoot) { throw 'Native RustDesk config remains.' }
    New-Item -ItemType Directory -Path $ArchiveParent -Force | Out-Null
    Move-Item -LiteralPath $TrialRoot -Destination $Archive
    if ((Test-Path -LiteralPath $TrialRoot) -or -not (Test-Path -LiteralPath (Join-Path $Archive 'trial-state.json'))) { throw 'Archive readback failed.' }
    $Result.Archive = $Archive
    $Result.Completed = $true
    $Result.CompletedAt = [DateTimeOffset]::Now.ToString('o')
} catch {
    $Result.Error = $_.Exception.Message
    Write-Error $_ -ErrorAction Continue
} finally {
    if (Test-Path -LiteralPath (Split-Path -Parent $StatusPath)) {
        [IO.File]::WriteAllText($StatusPath, ($Result | ConvertTo-Json -Depth 4), $Utf8)
    }
}
if (-not $Result.Completed) { exit 1 }
Write-Output 'RustDesk trial and its native configuration archived; four owned rules removed. Tailscale and DSH preserved.'
