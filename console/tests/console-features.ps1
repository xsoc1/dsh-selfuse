param([switch]$Binary)

$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $PSScriptRoot
$GuiSource = Join-Path $PackageRoot 'gui-src\DshControlApp.cs'
$PollerSource = Get-Content -LiteralPath (Join-Path $PackageRoot 'dsh-gui-poller.ps1') -Raw -Encoding UTF8
$Failures = @()

if ($Binary) {
    $Bytes = [System.IO.File]::ReadAllBytes((Join-Path $PackageRoot 'dsh-control-gui.exe'))
    [System.Reflection.Assembly]::Load($Bytes) | Out-Null
}
else {
    Add-Type -Path $GuiSource -ReferencedAssemblies @('System.dll', 'System.Core.dll', 'System.Windows.Forms.dll', 'System.Drawing.dll', 'System.Web.Extensions.dll')
}
$Settings = New-Object DshControl.GuiSettings
$Settings.BannerHeight = 0
$Settings.BannerImagePath = ''
$Form = New-Object DshControl.MainForm -ArgumentList @($Settings, $false)
try {
    $Flags = [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic
    $Buttons = $Form.GetType().GetField('btnPanel', $Flags).GetValue($Form).Controls
    $Labels = @($Buttons | ForEach-Object { $_.Text })
    foreach ($Label in @('启动', '停止', '重启', '打开 Web UI', '查看日志', '刷新', '配置目录', '复制诊断', '远程体检', '更新预检', '⚙ 设置')) {
        if ($Label -notin $Labels) { $Failures += "missing daily control: $Label" }
    }
    foreach ($Label in @('远程重启', 'Tailscale修复', '检查更新', '更新 DSH', '重启 WSL', '清空日志', 'web profile')) {
        if ($Label -in $Labels) { $Failures += "obsolete control remains: $Label" }
    }
    $Banner = $Form.GetType().GetField('bannerBox', $Flags).GetValue($Form)
    if ($Banner.ContextMenuStrip.Items.Count -ne 1) { $Failures += 'banner settings menu has duplicate entries' }
    $StatusLabels = $Form.GetType().GetField('statusLabels', $Flags).GetValue($Form)
    if ($StatusLabels.ContainsKey('DSH版本')) { $Failures += 'mirror version is presented as runtime version' }
}
finally { $Form.Dispose() }

$Normalize = [DshControl.GuiSettings].GetMethod('NormalizeDshHome')
if (-not $Normalize) {
    $Failures += 'legacy Windows DSH_HOME has no migration'
}
else {
    $LegacyHome = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.dsh'
    $ActiveHome = '\\wsl.localhost\Ubuntu\home\huangzy\.dsh'
    if ([DshControl.GuiSettings]::NormalizeDshHome([string]$LegacyHome) -ne $ActiveHome) { $Failures += 'legacy Windows DSH_HOME is not mapped to active WSL home' }
    if ([DshControl.GuiSettings]::NormalizeDshHome('D:\custom-dsh') -ne 'D:\custom-dsh') { $Failures += 'custom DSH_HOME was overwritten' }
}

foreach ($Action in @('wsl', 'tailscale', 'check-update', 'update-dsh')) {
    if ($PollerSource -match "'$Action'\s*\{") { $Failures += "obsolete poller action remains: $Action" }
}
if ($PollerSource -match 'function Repair-TailscaleAction|\$UpdateScript') { $Failures += 'obsolete helper or update script parameter remains' }
foreach ($Action in @('remote-health', 'update-preflight')) {
    if ($PollerSource -notmatch "'$Action'\s*\{") { $Failures += "missing read-only poller action: $Action" }
}
if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'dsh-gui-probes.ps1'))) { $Failures += 'diagnostic probe script is missing' }
if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot 'dsh-update-preflight.sh'))) { $Failures += 'WSL preflight script is missing' }

if ($Failures.Count -gt 0) {
    foreach ($Failure in $Failures) { Write-Host "RED $Failure" }
    exit 1
}
Write-Host 'GREEN console feature audit passed'
