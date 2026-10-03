# Narrow recovery only after an already-requested service stop has stalled.
[CmdletBinding()]
param([switch]$Apply)
$ErrorActionPreference = 'Stop'
if (-not $Apply) { throw 'Explicit -Apply required for a stalled-service recovery.' }
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator PowerShell required.' }
$Root = 'F:\Apps\DeepSeekHarnessRemote'
$Change = Get-Content -LiteralPath (Join-Path $Root 'tailscale-direct-change.json') -Raw | ConvertFrom-Json
if (-not $Change.otherBytesPreserved -or $Change.removedFlag -ne 'TS_DEBUG_ALWAYS_USE_DERP') { throw 'Expected scoped change receipt missing.' }
if (([DateTime]::UtcNow - [DateTime]::Parse($Change.time).ToUniversalTime()).TotalSeconds -lt 60) { throw 'Allow normal stop to complete before narrow recovery.' }
$Service = Get-CimInstance Win32_Service -Filter "Name='Tailscale'"
if ($Service.State -ne 'Stop Pending' -or $Service.ProcessId -eq 0) { throw 'Not a stalled Tailscale stop; inspect instead.' }
$TargetPid = [uint32]$Service.ProcessId
$Parent = Get-CimInstance Win32_Process -Filter "ProcessId=$TargetPid"
$ExpectedExecutable = 'C:\Program Files\Tailscale\tailscaled.exe'
if ($Parent.ExecutablePath -ine $ExpectedExecutable) { throw 'Service executable identity mismatch.' }
if ((Get-AuthenticodeSignature -LiteralPath $ExpectedExecutable).Status -ne 'Valid') { throw 'Tailscale executable signature not valid.' }
$Children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$TargetPid AND Name='tailscaled.exe'")
foreach ($Child in $Children) {
    if ($Child.ExecutablePath -ine $ExpectedExecutable) { throw 'Child executable identity mismatch.' }
}
$Still = Get-CimInstance Win32_Service -Filter "Name='Tailscale'"
if ($Still.ProcessId -ne $TargetPid -or $Still.State -ne 'Stop Pending') { throw 'Service state changed; no process termination.' }
foreach ($Child in $Children) { Stop-Process -Id $Child.ProcessId -Force -ErrorAction Stop }
$CurrentParent = Get-CimInstance Win32_Process -Filter "ProcessId=$TargetPid"
if ($CurrentParent) {
    if ($CurrentParent.ExecutablePath -ine $ExpectedExecutable -or $CurrentParent.CreationDate -ne $Parent.CreationDate) { throw 'Process identity changed.' }
    Stop-Process -Id $TargetPid -Force -ErrorAction Stop
}
$Recovery = [ordered]@{ time = [DateTime]::UtcNow.ToString('o'); parentPid = $TargetPid;
    terminatedChildPids = @($Children | ForEach-Object ProcessId); serviceStarted = $false; unrelatedProcessesTouched = $false }
$RecoveryPath = Join-Path $Root 'tailscale-stalled-recovery.json'
[IO.File]::WriteAllText($RecoveryPath, ($Recovery | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
$Controller = Get-Service Tailscale
$Controller.Refresh()
if ($Controller.Status -eq [ServiceProcess.ServiceControllerStatus]::StopPending) {
    try { $Controller.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds(20)) }
    catch {
        $Controller.Refresh()
        if ($Controller.Status -ne [ServiceProcess.ServiceControllerStatus]::Running) { throw }
    }
}
$Controller.Refresh()
if ($Controller.Status -eq [ServiceProcess.ServiceControllerStatus]::Stopped) { Start-Service -Name Tailscale }
(Get-Service Tailscale).WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(20))
$Recovery.serviceStarted = $true
[IO.File]::WriteAllText($RecoveryPath, ($Recovery | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
Write-Output ($Recovery | ConvertTo-Json -Compress)
