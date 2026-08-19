# dsh 一键控制台 (dsh-control.ps1)
# 用法:
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1           交互菜单
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 start     启动 dsh
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 restart   重启 dsh
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 stop      停止 dsh
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 status    查看状态
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 ui        打开 Web UI
#   powershell -NoProfile -ExecutionPolicy Bypass -File dsh-control.ps1 logs      查看最近日志
# 非管理员运行时自动提权重启 (会弹 UAC)。桌面快捷方式默认进入交互菜单。

$ErrorActionPreference = 'Continue'

# ============ 配置区 ============
$RepoRoot = Split-Path -Parent $PSScriptRoot
$HarnessRoot = Join-Path $RepoRoot 'vendor\deepseek-harness'
if (-not (Test-Path (Join-Path $HarnessRoot 'package.json'))) {
    if ($env:DSH_ROOT -and (Test-Path (Join-Path $env:DSH_ROOT 'package.json'))) {
        $HarnessRoot = $env:DSH_ROOT
    } else {
        $HarnessRoot = 'F:\tools\deepseek-harness'
    }
}
$WatchdogFile = Join-Path $HarnessRoot 'dsh-watchdog.ps1'
$WatchdogLog  = Join-Path $HarnessRoot 'dsh-watchdog.log'
$WebLog       = Join-Path $HarnessRoot 'dsh-web.log'
$WebUrl       = 'http://127.0.0.1:3080'
$WebPort      = 3080
$OllamaPort   = 11810
$OllamaUrl    = "http://127.0.0.1:$OllamaPort"
$OllamaCmd    = Get-Command ollama.exe -ErrorAction SilentlyContinue
$OllamaExe    = if ($OllamaCmd) { $OllamaCmd.Source } else { 'F:\tools\ollama\ollama.exe' }

# 附加启动项: 每次"启动/重启"时顺带检查并拉起。
#   Enabled - $false 时临时停用
#   Port    - 探活端口; 0 表示不探活
#   StartCmd- 未运行时执行的启动命令; '' 表示仅提示不自动启动
#   Note    - 展示用备注
$Extras = @(
    @{ Name = 'Ollama (dsh-vision 视觉依赖)'; Enabled = $true; Port = $OllamaPort; StartCmd = 'ollama serve'; Note = $OllamaUrl }
)
# ============ 配置区结束 ============

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Info($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[-] $msg" -ForegroundColor Red }

function Test-PortOpen([int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if ($ok) {
            $client.EndConnect($iar)
            $client.Close()
            return $true
        }
        $client.Close()
        return $false
    } catch {
        return $false
    }
}

function Get-OllamaCommand {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if (Test-Path $OllamaExe) { return $OllamaExe }
    return $null
}

function Get-WatchdogProcess {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe') -and
            $_.CommandLine -like '*dsh-watchdog.ps1*' -and
            $_.CommandLine -notlike '*ensure-dsh-watchdog.ps1*' -and
            $_.CommandLine -notlike '*dsh-control.ps1*' -and
            $_.CommandLine -notlike '*dsh-gui-poller.ps1*'
        }
}

function Start-Watchdog {
    if (Get-WatchdogProcess) {
        Write-Info 'watchdog 已在运行'
        return
    }
    Write-Info '启动 watchdog ...'
    Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$WatchdogFile" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    if (Get-WatchdogProcess) {
        Write-Ok 'watchdog 已启动'
    } else {
        Write-Err 'watchdog 启动失败'
    }
}

function Wait-WebReady([int]$TimeoutSec = 180) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        try {
            $r = Invoke-WebRequest -Uri $WebUrl -UseBasicParsing -TimeoutSec 5
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
    }
    return $false
}

function Stop-DshAll {
    $ids = New-Object System.Collections.Generic.HashSet[int]
    $lines = @(netstat -ano | Where-Object { $_ -match "TCP\s" -and $_ -match ":${WebPort}\s" -and $_ -match "LISTENING" })
    foreach ($line in $lines) {
        $parts = ($line.Trim() -split '\s+')
        if ($parts.Count -ge 5) {
            $procId = 0
            if ([int]::TryParse($parts[-1], [ref]$procId) -and $procId -gt 0) { [void]$ids.Add($procId) }
        }
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe' -or $_.Name -eq 'node.exe' -or $_.Name -eq 'cmd.exe') -and
            ($_.CommandLine -like '*run-dsh-web.ps1*' -or $_.CommandLine -like '*apps/cli/src/bin.ts*')
        } | ForEach-Object { [void]$ids.Add([int]$_.ProcessId) }
    Get-WatchdogProcess | ForEach-Object { [void]$ids.Add([int]$_.ProcessId) }
    foreach ($id in $ids) { taskkill /PID $id /T /F 2>&1 | Out-Null }
    Start-Sleep -Seconds 2
    if (Test-PortOpen $WebPort) {
        Write-Warn '端口 3080 仍被占用'
    } else {
        Write-Ok 'dsh 已全部停止'
    }
}

function Start-Extras {
    foreach ($e in $Extras) {
        if (-not $e.Enabled) { continue }
        if ($e.Port -gt 0 -and (Test-PortOpen $e.Port)) {
            Write-Ok "$($e.Name) 已在运行 ($($e.Note))"
            continue
        }
        if ($e.StartCmd) {
            $parts = $e.StartCmd -split ' '
            $exe = $parts[0]
            if ($exe -eq 'ollama') { $exe = Get-OllamaCommand }
            $extraArgs = @($parts | Select-Object -Skip 1)
            if (Get-Command $exe -ErrorAction SilentlyContinue) {
                Write-Info "启动 $($e.Name) ..."
                $oldOllamaHost = $env:OLLAMA_HOST
                if ($exe -like '*ollama*') { $env:OLLAMA_HOST = "127.0.0.1:$OllamaPort" }
                Start-Process -FilePath $exe -ArgumentList $extraArgs -WindowStyle Hidden
                if ($null -eq $oldOllamaHost) { Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue } else { $env:OLLAMA_HOST = $oldOllamaHost }
                Write-Ok "$($e.Name) 启动命令已发出"
            } else {
                Write-Warn "$($e.Name): 未找到命令 '$exe'，请手动安装/启动"
            }
        } else {
            Write-Warn "$($e.Name) 未运行 (仅提示)"
        }
    }
}

function Show-Status {
    Write-Host ''
    Write-Host '---- dsh 状态 ----' -ForegroundColor Cyan
    $webUp = Test-PortOpen $WebPort
    $http = ''
    if ($webUp) {
        try {
            $r = Invoke-WebRequest -Uri $WebUrl -UseBasicParsing -TimeoutSec 5
            $http = "HTTP $($r.StatusCode)"
        } catch {
            $http = '端口开但 HTTP 无响应'
        }
    }
    Write-Host ("  web     : " + $(if ($webUp) { "运行中 ($http)" } else { '未运行' }))
    $wd = Get-WatchdogProcess
    if ($wd) {
        $pids = ($wd | ForEach-Object { $_.ProcessId }) -join ','
        Write-Host "  watchdog: 运行中 (PID $pids)"
    } else {
        Write-Host '  watchdog: 未运行'
    }
    $wslText = (wsl -l -v 2>&1 | Out-String) -replace "`0", ''
    if ($wslText -match 'Running') { $wslState = 'Running' }
    elseif ($wslText -match 'Stopped') { $wslState = 'Stopped' }
    else { $wslState = '未知' }
    Write-Host ("  WSL     : $wslState (虚拟 linux)")
    if (Test-PortOpen $OllamaPort) {
        Write-Host '  ollama  : 运行中'
    } else {
        Write-Host '  ollama  : 未运行 (dsh-vision 视觉功能不可用)' -ForegroundColor Yellow
    }
    Write-Host ''
}

function Show-Logs {
    Write-Host '---- watchdog.log (尾部 12 行) ----' -ForegroundColor Cyan
    if (Test-Path $WatchdogLog) { Get-Content $WatchdogLog -Tail 12 -Encoding UTF8 } else { Write-Warn '无 watchdog 日志' }
    Write-Host '---- dsh-web.log (尾部 12 行) ----' -ForegroundColor Cyan
    if (Test-Path $WebLog) { Get-Content $WebLog -Tail 12 -Encoding UTF8 } else { Write-Warn '无 web 日志' }
}

function Action-Start {
    Write-Host '---- 启动 dsh ----' -ForegroundColor Cyan
    Start-Watchdog
    if (Wait-WebReady) {
        Write-Ok "dsh 已就绪: $WebUrl"
    } else {
        Write-Warn 'web 未在预期时间内就绪，watchdog 会在后台继续处理'
    }
    Start-Extras
}

function Action-Restart {
    Write-Host '---- 重启 dsh ----' -ForegroundColor Cyan
    Stop-DshAll
    Start-Watchdog
    if (Wait-WebReady) {
        Write-Ok "dsh 已重启就绪: $WebUrl"
    } else {
        Write-Warn 'web 未在预期时间内就绪，watchdog 会在后台继续处理'
    }
    Start-Extras
}

function Action-Wsl {
    Write-Host '---- WSL (虚拟 linux) ----' -ForegroundColor Cyan
    (wsl -l -v 2>&1 | Out-String) -replace "`0", ''
    Write-Host ''
    $r = Read-Host '  重启 WSL? (y/N)'
    if ($r -match '^[yY]') {
        Write-Info '正在关闭 WSL ...'
        wsl --shutdown
        Start-Sleep -Seconds 2
        (wsl -l -v 2>&1 | Out-String) -replace "`0", ''
        Write-Info '下次 dsh 使用 wsl_bash 时会自动重新启动'
    }
}

function Show-Menu {
    Clear-Host
    Write-Host '==================================================' -ForegroundColor DarkGray
    Write-Host '              dsh 一键控制台' -ForegroundColor Cyan
    Write-Host '==================================================' -ForegroundColor DarkGray
    Show-Status
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  1) 启动 dsh        4) 打开 Web UI     7) Ollama 检查/启动'
    Write-Host '  2) 重启 dsh        5) 查看状态        8) WSL 检查/重启'
    Write-Host '  3) 停止 dsh        6) 查看最近日志     0) 退出'
    Write-Host '--------------------------------------------------' -ForegroundColor DarkGray
}

function Action-Ollama {
    Write-Host '---- Ollama (dsh-vision 依赖) ----' -ForegroundColor Cyan
    if (Test-PortOpen $OllamaPort) {
        Write-Ok "Ollama 运行中: $OllamaUrl"
    } else {
        Write-Warn 'Ollama 未运行'
        $r = Read-Host '  尝试启动 ollama serve? (y/N)'
        if ($r -match '^[yY]') {
            $ollama = Get-OllamaCommand
            if ($ollama) {
                $oldOllamaHost = $env:OLLAMA_HOST
                $env:OLLAMA_HOST = "127.0.0.1:$OllamaPort"
                Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden
                if ($null -eq $oldOllamaHost) { Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue } else { $env:OLLAMA_HOST = $oldOllamaHost }
                Write-Ok 'ollama serve 启动命令已发出'
            } else {
                Write-Err "未找到 'ollama'，请先安装 (https://ollama.com)"
            }
        }
    }
}

# ---- 自提权: 非管理员时用 RunAs 重新启动自己 ----
if (-not (Test-Admin)) {
    Write-Host '需要管理员权限，正在以管理员身份重新启动...' -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") + @($args)
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -WorkingDirectory (Split-Path $PSCommandPath)
    exit
}

# ---- 入口 ----
$mode = $args[0]
switch ($mode) {
    'start' {
        Action-Start
        Write-Host ''
        Read-Host '按回车退出'
    }
    'restart' {
        Action-Restart
        Write-Host ''
        Read-Host '按回车退出'
    }
    'stop' {
        Stop-DshAll
        Write-Host ''
        Read-Host '按回车退出'
    }
    'status' {
        Show-Status
    }
    'ui' {
        Start-Process $WebUrl
        Write-Ok "已打开 $WebUrl"
    }
    'logs' {
        Show-Logs
        Write-Host ''
        Read-Host '按回车退出'
    }
    default {
        while ($true) {
            Show-Menu
            $choice = Read-Host '  请选择'
            switch ($choice) {
                '1' { Action-Start; Read-Host '按回车返回菜单' }
                '2' { Action-Restart; Read-Host '按回车返回菜单' }
                '3' { Stop-DshAll; Read-Host '按回车返回菜单' }
                '4' { Start-Process $WebUrl; Write-Ok "已打开 $WebUrl"; Read-Host '按回车返回菜单' }
                '5' { Show-Status; Read-Host '按回车返回菜单' }
                '6' { Show-Logs; Read-Host '按回车返回菜单' }
                '7' { Action-Ollama; Read-Host '按回车返回菜单' }
                '8' { Action-Wsl; Read-Host '按回车返回菜单' }
                '0' { exit }
                default { Write-Warn '无效选择' }
            }
        }
    }
}
