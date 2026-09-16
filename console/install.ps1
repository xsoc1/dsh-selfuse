# install.ps1 - DeepSeek Harness 控制台一键安装与快捷方式配置脚本
param(
    [switch]$NoLaunch
)
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir 'dsh-control-gui.exe'
$ico = Join-Path $dir 'dsh.ico'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " DeepSeek Harness 控制台 一键配置向导" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "安装目录: $dir"

if (-not (Test-Path $exe)) {
    Write-Host "[!] 未找到控制台主程序: $exe，正在尝试重新编译..." -ForegroundColor Yellow
    $buildScript = Join-Path $dir 'build-gui-exe.ps1'
    if (Test-Path $buildScript) {
        & powershell.exe -ExecutionPolicy Bypass -File $buildScript
    }
}

if (-not (Test-Path $exe)) {
    throw "未找到控制台主程序: $exe"
}

$wsh = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($name in @('DSH Control.lnk', 'DSH控制台.lnk')) {
    $scPath = Join-Path $desktop $name
    $sc = $wsh.CreateShortcut($scPath)
    $sc.TargetPath = $exe
    $sc.WorkingDirectory = $dir
    $sc.Description = 'DeepSeek Harness 控制台'
    if (Test-Path $ico) { $sc.IconLocation = $ico }
    $sc.Save()
    Write-Host "[+] 已创建桌面快捷方式: $scPath" -ForegroundColor Green
}

$startMenu = [Environment]::GetFolderPath('StartMenu')
$programs = Join-Path $startMenu 'Programs\DeepSeek Harness'
if (-not (Test-Path $programs)) { New-Item -ItemType Directory -Path $programs -Force | Out-Null }
$scStart = Join-Path $programs 'DSH 控制台.lnk'
$sc = $wsh.CreateShortcut($scStart)
$sc.TargetPath = $exe
$sc.WorkingDirectory = $dir
$sc.Description = 'DeepSeek Harness 控制台'
if (Test-Path $ico) { $sc.IconLocation = $ico }
$sc.Save()
Write-Host "[+] 已创建「开始」菜单快捷方式: $scStart" -ForegroundColor Green

Write-Host "`n[✓] 控制台安装与快捷方式配置完成！" -ForegroundColor Green

if (-not $NoLaunch) {
    Write-Host "[*] 正在启动控制台..." -ForegroundColor Cyan
    Start-Process -FilePath $exe -WorkingDirectory $dir
}
