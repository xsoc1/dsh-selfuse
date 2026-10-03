# Remove one obsolete debug override, preserving every unrelated byte and Serve mapping.
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'

function Remove-ForcedDerpBytes {
    param([byte[]]$Bytes)
    $Utf8 = New-Object Text.UTF8Encoding($false, $true)
    $Text = $Utf8.GetString($Bytes)
    $Prefix = ''
    if ($Text.Length -gt 0 -and $Text[0] -eq [char]0xFEFF) { $Prefix = [string][char]0xFEFF; $Text = $Text.Substring(1) }
    if ($Text.Contains([string][char]0)) { throw 'Only a valid UTF-8 service environment is supported.' }
    $AllFlags = [regex]::Matches($Text, '(?m)^[ \t]*TS_DEBUG_ALWAYS_USE_DERP[ \t]*=[ \t]*([^\r\n]*)')
    if ($AllFlags.Count -ne 1 -or $AllFlags[0].Groups[1].Value.Trim() -ne '1') {
        throw 'Expected exactly one active forced-DERP=1 override; inspect instead of overwriting.'
    }
    $Pattern = '(?m)^[ \t]*TS_DEBUG_ALWAYS_USE_DERP[ \t]*=[ \t]*1[ \t]*(?:\r?\n|$)'
    $MatchesToRemove = [regex]::Matches($Text, $Pattern)
    if ($MatchesToRemove.Count -ne 1) { throw 'Unsupported environment line syntax.' }
    $Match = $MatchesToRemove[0]
    $NewText = $Text.Remove($Match.Index, $Match.Length)
    return ,($Utf8.GetBytes($Prefix + $NewText))
}

function Read-ServeConfig {
    $Info = New-Object Diagnostics.ProcessStartInfo
    $Info.FileName = 'C:\Program Files\Tailscale\tailscale.exe'
    $Info.Arguments = 'serve status --json'
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $true
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $Process = New-Object Diagnostics.Process
    $Process.StartInfo = $Info
    try {
        if (-not $Process.Start()) { throw 'Serve probe did not start.' }
        $Output = $Process.StandardOutput.ReadToEndAsync()
        $Errors = $Process.StandardError.ReadToEndAsync()
        if (-not $Process.WaitForExit(5000)) { $Process.Kill(); throw 'Serve probe timed out.' }
        if ($Process.ExitCode -ne 0) { throw 'Serve probe failed.' }
        return (($Output.Result | ConvertFrom-Json) | ConvertTo-Json -Depth 20 -Compress)
    } finally { $Process.Dispose() }
}

if ($MyInvocation.InvocationName -eq '.') { return }
if (-not $Apply) { throw 'This changes a service setting and restarts Tailscale; inspect first and explicitly pass -Apply.' }
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator PowerShell required.' }
$Root = 'F:\Apps\DeepSeekHarnessRemote'
$EnvPath = 'C:\ProgramData\Tailscale\tailscaled-env.txt'
$TailscaleExe = 'C:\Program Files\Tailscale\tailscale.exe'
& (Join-Path $PSScriptRoot 'inspect-tailscale-service-env.ps1') | Out-Null
$Inspection = Get-Content -LiteralPath (Join-Path $Root 'tailscale-service-env-inspection.json') -Raw | ConvertFrom-Json
if (-not $Inspection.forcedDerp -or $Inspection.activeFlagCount -ne 1) { throw 'Native service environment is not the expected forced-DERP configuration.' }
$Original = [IO.File]::ReadAllBytes($EnvPath)
$Updated = Remove-ForcedDerpBytes $Original
$BeforeHash = (Get-FileHash -LiteralPath $EnvPath -Algorithm SHA256).Hash
$ServeBefore = Read-ServeConfig
$Backup = Join-Path $Root ('tailscale-before-direct-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $Backup -ErrorAction Stop | Out-Null
[IO.File]::WriteAllBytes((Join-Path $Backup 'tailscaled-env.txt'), $Original)
[IO.File]::WriteAllText((Join-Path $Backup 'serve-before.json'), $ServeBefore, (New-Object Text.UTF8Encoding($false)))
if ((Get-FileHash -LiteralPath (Join-Path $Backup 'tailscaled-env.txt') -Algorithm SHA256).Hash -ne $BeforeHash) { throw 'Backup hash mismatch.' }
$OriginalAcl = Get-Acl -LiteralPath $EnvPath
$TempPath = $EnvPath + '.dsh-direct-' + [Guid]::NewGuid().ToString('N') + '.tmp'
try {
    [IO.File]::WriteAllBytes($TempPath, $Updated)
    Set-Acl -LiteralPath $TempPath -AclObject $OriginalAcl
    if ((Get-FileHash -LiteralPath $EnvPath -Algorithm SHA256).Hash -ne $BeforeHash) { throw 'Environment changed during preparation; not replacing.' }
    Move-Item -LiteralPath $TempPath -Destination $EnvPath -Force
    $Actual = [IO.File]::ReadAllBytes($EnvPath)
    if ([Convert]::ToBase64String($Actual) -cne [Convert]::ToBase64String($Updated)) { throw 'Environment readback mismatch.' }
    $Receipt = [ordered]@{ time = [DateTime]::UtcNow.ToString('o'); backup = $Backup; beforeHash = $BeforeHash;
        afterHash = (Get-FileHash -LiteralPath $EnvPath -Algorithm SHA256).Hash; removedFlag = 'TS_DEBUG_ALWAYS_USE_DERP';
        otherBytesPreserved = $true; serviceRestarted = $false; serveUnchanged = $false }
    $ReceiptPath = Join-Path $Root 'tailscale-direct-change.json'
    [IO.File]::WriteAllText($ReceiptPath, ($Receipt | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $Controller = Get-Service Tailscale
    $Controller.Stop()
    try { $Controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(20)) }
    catch { throw 'Tailscale stop timed out; use the separately guarded stalled-stop recovery, then inspect.' }
    Start-Service -Name Tailscale -ErrorAction Stop
    (Get-Service Tailscale).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))
    $Receipt.serviceRestarted = $true
    for ($Attempt = 0; $Attempt -lt 10; $Attempt++) {
        try { $Receipt.serveUnchanged = $ServeBefore -ceq (Read-ServeConfig) } catch { $Receipt.serveUnchanged = $false }
        if ($Receipt.serveUnchanged) { break }
        Start-Sleep -Seconds 1
    }
    [IO.File]::WriteAllText($ReceiptPath, ($Receipt | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    if (-not $Receipt.serveUnchanged) { throw 'Serve changed; preserved backup, inspect before further action.' }
    & (Join-Path $PSScriptRoot 'inspect-tailscale-service-env.ps1') | Out-Null
    Write-Output ($Receipt | ConvertTo-Json -Compress)
} finally {
    if (Test-Path -LiteralPath $TempPath -PathType Leaf) { Remove-Item -LiteralPath $TempPath }
}
