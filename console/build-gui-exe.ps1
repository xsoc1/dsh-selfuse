# build-gui-exe.ps1
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot 'dsh-control-gui.exe'),
    [switch]$CreateDesktopShortcut
)

$ErrorActionPreference = 'Stop'

$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
    $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path $csc)) {
    throw 'Cannot find .NET Framework csc.exe'
}

$csSrc = Join-Path $PSScriptRoot 'gui-src\DshControlApp.cs'
$manifest = Join-Path $PSScriptRoot 'gui-src\app.manifest'
$icon = Join-Path $PSScriptRoot 'dsh.ico'
if (-not (Test-Path $icon)) {
    $icon = Join-Path $PSScriptRoot '..\..\..\dsh.ico'
}

if (-not (Test-Path $csSrc)) { throw "Source file not found: $csSrc" }
if (-not (Test-Path $manifest)) { throw "Manifest file not found: $manifest" }

Write-Host "[i] Compiling DSH Control GUI standalone executable..." -ForegroundColor Cyan
Write-Host "    Compiler : $csc"
Write-Host "    Source   : $csSrc"
Write-Host "    Output   : $OutputPath"

$cmdArgs = @(
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    "/win32manifest:`"$manifest`"",
    '/r:System.dll',
    '/r:System.Core.dll',
    '/r:System.Windows.Forms.dll',
    '/r:System.Drawing.dll',
    '/r:System.Web.Extensions.dll',
    "/out:`"$OutputPath`"",
    "`"$csSrc`""
)

if (Test-Path $icon) {
    $cmdArgs += "/win32icon:`"$icon`""
}

$compiler = Start-Process -FilePath $csc -ArgumentList $cmdArgs -Wait -PassThru -NoNewWindow
if ($compiler.ExitCode -ne 0) {
    throw "Compilation failed with exit code $($compiler.ExitCode)"
}

if (-not (Test-Path $OutputPath)) {
    throw "Target binary not found: $OutputPath"
}

$fileInfo = Get-Item $OutputPath
$sizeKb = [Math]::Round($fileInfo.Length / 1024, 1)
Write-Host "[+] Compilation success! Binary size: $($fileInfo.Length) bytes ($sizeKb KB)" -ForegroundColor Green

if ($CreateDesktopShortcut) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $desktop = [Environment]::GetFolderPath('Desktop')
        foreach ($name in @('DSH Control.lnk', 'DSH控制台.lnk')) {
            $shortcut = $wsh.CreateShortcut((Join-Path $desktop $name))
            $shortcut.TargetPath = $OutputPath
            $shortcut.WorkingDirectory = Split-Path $OutputPath
            $shortcut.Description = 'DeepSeek Harness 控制台'
            if (Test-Path $icon) { $shortcut.IconLocation = $icon }
            $shortcut.Save()
            Write-Host "[+] Desktop shortcut created: $desktop\$name" -ForegroundColor Green
        }
    } catch {
        Write-Host "[!] Failed to create desktop shortcut: $_" -ForegroundColor Yellow
    }
}
