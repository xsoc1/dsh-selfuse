param()

$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $PSScriptRoot
$PollerPath = Join-Path $PackageRoot 'dsh-gui-poller.ps1'
$GuiSource = Join-Path $PackageRoot 'gui-src\DshControlApp.cs'
$Failures = @()

$Tokens = $null
$ParseErrors = $null
$Ast = [System.Management.Automation.Language.Parser]::ParseFile($PollerPath, [ref]$Tokens, [ref]$ParseErrors)
if ($ParseErrors.Count -gt 0) { throw 'poller parse failed' }
$TailscaleFunction = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Get-TailscaleInfo' }, $true) | Select-Object -First 1
if (-not $TailscaleFunction) { throw 'Get-TailscaleInfo not found' }
Invoke-Expression $TailscaleFunction.Extent.Text
$ReadyFunction = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Node.Name -eq 'Test-WebReady' }, $true) | Select-Object -First 1
if (-not $ReadyFunction) {
    $Failures += 'Poller: no web readiness decision'
}
else {
    Invoke-Expression $ReadyFunction.Extent.Text
    if (Test-WebReady $true 'HTTP no response') { $Failures += 'Poller: open port without HTTP shown ready' }
    if (-not (Test-WebReady $true 'HTTP 200')) { $Failures += 'Poller: healthy Web shown down' }
    if (Test-WebReady $false '') { $Failures += 'Poller: closed port shown ready' }
}

function Resolve-TailscaleExe { return 'mock-ts' }
function Get-Service { [CmdletBinding()] param([string]$Name) return [pscustomobject]@{ Status = $script:ServiceState } }
function Invoke-TailscaleCommand {
    param([string]$Path, [string[]]$CommandArgs)
    if ($CommandArgs[0] -eq 'status') {
        if ($script:BackendState -eq 'Error') { return @{ ok = $false; output = '' } }
        return @{ ok = $true; output = ('{"BackendState":"' + $script:BackendState + '","Self":{"TailscaleIPs":["100.64.0.1"]}}') }
    }
    return @{ ok = $true; output = 'https://test.ts.net' }
}
function mock-ts {
    param([string]$Verb)
    if ($Verb -eq 'status') {
        if ($script:BackendState -eq 'Error') {
            $global:LASTEXITCODE = 1
            return 'failed to connect to local tailscaled'
        }
        $global:LASTEXITCODE = 0
        return '{"BackendState":"' + $script:BackendState + '","Self":{"TailscaleIPs":["100.64.0.1"]}}'
    }
    if ($Verb -eq 'ip') { return '100.64.0.1' }
    if ($Verb -eq 'serve') { return 'https://test.ts.net' }
}

foreach ($Case in @(
    @{ Name = 'service stopped'; Service = 'Stopped'; Backend = 'Error'; Connected = $false },
    @{ Name = 'daemon command failed'; Service = 'Running'; Backend = 'Error'; Connected = $false },
    @{ Name = 'VPN switched off'; Service = 'Running'; Backend = 'Stopped'; Connected = $false },
    @{ Name = 'connected'; Service = 'Running'; Backend = 'Running'; Connected = $true }
)) {
    $script:ServiceState = $Case.Service
    $script:BackendState = $Case.Backend
    $script:cachedTsInfo = $null
    $script:lastTsCheckAt = [datetime]::MinValue
    $Result = Get-TailscaleInfo -Force
    $Connected = $Result.status.StartsWith([string][char]0x5df2)
    if ($Connected -ne $Case.Connected) { $Failures += 'Tailscale: ' + $Case.Name }
}

$OriginalTemp = $env:TEMP
$OriginalTmp = $env:TMP
$TestDir = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-gui-status-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($TestDir) | Out-Null
try {
    $env:TEMP = $TestDir
    $env:TMP = $TestDir
    Add-Type -Path $GuiSource -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Windows.Forms.dll', 'System.Drawing.dll', 'System.Web.Extensions.dll')
    $Settings = New-Object DshControl.GuiSettings
    $Settings.BannerHeight = 0
    $Settings.BannerImagePath = ''
    $Form = New-Object DshControl.MainForm -ArgumentList @($Settings, $false)
    try {
        $Flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
        $Update = $Form.GetType().GetMethod('UpdateStatus', $Flags)
        $Labels = $Form.GetType().GetField('statusLabels', $Flags).GetValue($Form)
        $StatusFile = Join-Path $TestDir 'dsh-gui-status.json'
        $Green = [System.Drawing.Color]::ForestGreen.ToArgb()
        $Base = @{
            time = '12:00:00'; webUp = $true; webPortOpen = $true; http = 'HTTP no response'; webPid = '123'
            watchdogPids = ''; wsl = 'Running'; dshHome = $true; dshProfile = $true
            dshVersion = 'test'; tailscale = ([string][char]0x5df2 + [char]0x8fde + [char]0x63a5 + ' ')
            tailscaleIp = ''; tailscaleServe = ''; webLogTail = @(); watchdogLogTail = @(); activityLogTail = @()
        }
        [System.IO.File]::WriteAllText($StatusFile, ($Base | ConvertTo-Json -Compress))
        $Update.Invoke($Form, @()) | Out-Null
        if ($Labels['web'].ForeColor.ToArgb() -eq $Green) { $Failures += 'GUI: port-only web shown green' }
        if ($Labels['Tailscale'].ForeColor.ToArgb() -eq $Green) { $Failures += 'GUI: no-IP Tailscale shown green' }

        $Base.http = 'HTTP 200'
        $Base.tailscaleIp = '100.64.0.1'
        $Base.time = '12:00:01'
        [System.IO.File]::WriteAllText($StatusFile, ($Base | ConvertTo-Json -Compress))
        $Update.Invoke($Form, @()) | Out-Null
        if ($Labels['web'].ForeColor.ToArgb() -ne $Green) { $Failures += 'GUI: healthy web not shown green' }
        if ($Labels['Tailscale'].ForeColor.ToArgb() -ne $Green) { $Failures += 'GUI: connected Tailscale not shown green' }

        [System.IO.File]::WriteAllText($StatusFile, '')
        $Update.Invoke($Form, @()) | Out-Null
        if ($Labels['web'].ForeColor.ToArgb() -eq $Green) { $Failures += 'GUI: empty status kept web green' }
        if ($Labels['Tailscale'].ForeColor.ToArgb() -eq $Green) { $Failures += 'GUI: empty status kept Tailscale green' }

        [System.IO.File]::WriteAllText($StatusFile, ($Base | ConvertTo-Json -Compress))
        $Update.Invoke($Form, @()) | Out-Null
        [System.IO.File]::SetLastWriteTimeUtc($StatusFile, [datetime]::UtcNow.AddSeconds(-60))
        $Update.Invoke($Form, @()) | Out-Null
        if ($Labels['web'].ForeColor.ToArgb() -eq $Green) { $Failures += 'GUI: stale web shown green' }
        if ($Labels['Tailscale'].ForeColor.ToArgb() -eq $Green) { $Failures += 'GUI: stale Tailscale shown green' }
    }
    finally { $Form.Dispose() }
}
finally {
    $env:TEMP = $OriginalTemp
    $env:TMP = $OriginalTmp
    Remove-Item -LiteralPath $TestDir -Recurse -Force
}

if ($Failures.Count -gt 0) {
    foreach ($Failure in $Failures) { Write-Host ('RED ' + $Failure) }
    exit 1
}
Write-Host 'GREEN status regression cases passed'
