# build-installer.ps1 - 构建 DeepSeek Harness 控制台安装包
param(
    [string]$DownloadDir = (Join-Path $env:USERPROFILE 'Downloads')
)

$ErrorActionPreference = 'Stop'

$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $PSScriptRoot) { $PSScriptRoot = Get-Location }

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " DeepSeek Harness 控制台安装程序打包向导" -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# 1. 编译最新的控制台可执行文件
$buildGuiScript = Join-Path $PSScriptRoot 'build-gui-exe.ps1'
$exePath = Join-Path $PSScriptRoot 'dsh-control-gui.exe'
Write-Host "[1/5] Checking DSH Control GUI binary..." -ForegroundColor Yellow
$needBuildGui = $true
if (Test-Path $exePath) {
    $csSrc = Join-Path $PSScriptRoot 'gui-src\DshControlApp.cs'
    if ((Get-Item $exePath).LastWriteTime -ge (Get-Item $csSrc).LastWriteTime) {
        Write-Host "    Existing dsh-control-gui.exe is up-to-date, reusing." -ForegroundColor Green
        $needBuildGui = $false
    }
}
if ($needBuildGui) {
    & powershell.exe -ExecutionPolicy Bypass -File $buildGuiScript
    if ($LASTEXITCODE -ne 0) { throw "Build dsh-control-gui.exe failed" }
}
$iconPath = Join-Path $PSScriptRoot 'dsh.ico'
if (-not (Test-Path $exePath)) { throw "未找到控制台可执行文件: $exePath" }

# 2. 准备打包目录
Write-Host "[2/5] 准备安装包组件文件..." -ForegroundColor Yellow
$tempStaging = Join-Path $env:TEMP ('dsh-installer-staging-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path $tempStaging) { Remove-Item $tempStaging -Recurse -Force }
New-Item -ItemType Directory -Path $tempStaging -Force | Out-Null

$filesToInclude = @(
    'dsh-control-gui.exe',
    'dsh-gui-poller.ps1',
    'dsh.ico',
    'build-gui-exe.ps1',
    'install.ps1',
    'install.bat',
    'package.json',
    'README.md'
)

foreach ($f in $filesToInclude) {
    $src = Join-Path $PSScriptRoot $f
    if (Test-Path $src) {
        Copy-Item $src -Destination (Join-Path $tempStaging $f) -Force
    } else {
        Write-Warning "文件未找到: $src"
    }
}

# 复制源码
$guiSrcDir = Join-Path $PSScriptRoot 'gui-src'
if (Test-Path $guiSrcDir) {
    Copy-Item $guiSrcDir -Destination (Join-Path $tempStaging 'gui-src') -Recurse -Force
}

# 3. 压缩为 package.zip
Write-Host "[3/5] 打包为嵌入式核心数据包 (package.zip)..." -ForegroundColor Yellow
$tempZip = Join-Path $env:TEMP ('package-' + [Guid]::NewGuid().ToString('N') + '.zip')
if (Test-Path $tempZip) { Remove-Item $tempZip -Force }

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($tempStaging, $tempZip)

# 4. 编译安装向导 DshControl-Setup.exe
Write-Host "[4/5] 编译独立安装程序 (DshControl-Setup.exe)..." -ForegroundColor Yellow
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
    $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
}

$installerCs = Join-Path $PSScriptRoot 'installer-src\InstallerApp.cs'
$manifest = Join-Path $PSScriptRoot 'installer-src\app.manifest'
$distDir = Join-Path $PSScriptRoot 'dist'
if (-not (Test-Path $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }

$setupExe = Join-Path $distDir 'DshControl-Setup.exe'
$cmdArgs = @(
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    "/win32manifest:`"$manifest`"",
    '/r:System.dll',
    '/r:System.Core.dll',
    '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.IO.Compression.dll',
    '/r:System.IO.Compression.FileSystem.dll',
    "/resource:`"$tempZip`",package.zip",
    "/out:`"$setupExe`"",
    "`"$installerCs`""
)

if (Test-Path $iconPath) {
    $cmdArgs += "/win32icon:`"$iconPath`""
    $cmdArgs += "/resource:`"$iconPath`",dsh.ico"
}

& $csc $cmdArgs
if ($LASTEXITCODE -ne 0) { throw "编译安装程序失败，退出码: $LASTEXITCODE" }

# 同时制作独立的便携压缩包
$zipDist = Join-Path $distDir 'dsh-control-gui-v0.1.0-windows-x64.zip'
if (Test-Path $zipDist) { Remove-Item $zipDist -Force }
Copy-Item $tempZip $zipDist -Force

# 5. 复制到 Downloads 目录
Write-Host "[5/5] 输出安装包至 $DownloadDir..." -ForegroundColor Yellow
if (-not (Test-Path $DownloadDir)) {
    New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null
}

$finalSetup = Join-Path $DownloadDir 'DshControl-Setup.exe'
$finalZip = Join-Path $DownloadDir 'dsh-control-gui-v0.1.0-windows-x64.zip'

Copy-Item $setupExe $finalSetup -Force
Copy-Item $zipDist $finalZip -Force

# 清理临时文件
Remove-Item $tempStaging -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue

Write-Host "`n=================================================" -ForegroundColor Green
Write-Host " [✓] 打包完成！已成功放置于 Download 目录:" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green

$setupInfo = Get-Item $finalSetup
$setupKb = [Math]::Round($setupInfo.Length / 1024, 1)
$setupHash = (Get-FileHash $finalSetup -Algorithm SHA256).Hash

$zipInfo = Get-Item $finalZip
$zipKb = [Math]::Round($zipInfo.Length / 1024, 1)
$zipHash = (Get-FileHash $finalZip -Algorithm SHA256).Hash

Write-Host "1. 安装向导程序 (双击直接运行安装):" -ForegroundColor Cyan
Write-Host ('   路径  : ' + $finalSetup)
Write-Host ('   大小  : ' + $setupInfo.Length + ' 字节 (' + $setupKb + ' KB)')
Write-Host ('   SHA256: ' + $setupHash)

Write-Host "`n2. 完整便携压缩包 (解压即用 / 含一键脚本):" -ForegroundColor Cyan
Write-Host ('   路径  : ' + $finalZip)
Write-Host ('   大小  : ' + $zipInfo.Length + ' 字节 (' + $zipKb + ' KB)')
Write-Host ('   SHA256: ' + $zipHash)
