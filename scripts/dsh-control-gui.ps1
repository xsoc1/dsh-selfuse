# dsh 图形控制台 (dsh-control-gui.ps1)
# WinForms 简单界面: 实时状态 + 启动/重启/停止 + Web UI/日志/Ollama/WSL。
# 非管理员运行时自动提权重启 (会弹 UAC)。附加 -SmokeTest 参数用于自检 (3 秒后自动关闭)。

$ErrorActionPreference = 'Stop'

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
$IconFile     = Join-Path $HarnessRoot 'dsh.ico'
$WebUrl       = 'http://127.0.0.1:3080'
$WebPort      = 3080
$OllamaPort   = 11810
$OllamaExe    = 'F:\tools\ollama\ollama.exe'
$ImageFile    = 'C:\Users\HuangZY\Pictures\IMG_1891.PNG'
$DshHome      = Join-Path $env:USERPROFILE '.dsh'
$DshProfile   = Join-Path $DshHome 'profiles\web'
$StatusFile   = Join-Path $env:TEMP 'dsh-gui-status.json'
$TriggerFile  = Join-Path $env:TEMP 'dsh-gui-refresh.trigger'
$PollerFile   = Join-Path $env:TEMP 'dsh-gui-poller.ps1'
$CmdFile      = Join-Path $env:TEMP 'dsh-gui-cmd.json'
$ResultPrefix = Join-Path $env:TEMP 'dsh-gui-result-'
$ActivityFile = Join-Path $env:TEMP 'dsh-gui-activity.log'
$pollerProcess = $null
$lastStatusRaw = ''
$script:logTailReady = $false
# ============ 配置区结束 ============

$PollerScript = @'
param(
    [string]$StatusFile,
    [string]$TriggerFile,
    [string]$CmdFile,
    [string]$ResultPrefix,
    [string]$ActivityFile,
    [string]$WebUrl,
    [int]$WebPort,
    [int]$OllamaPort,
    [string]$OllamaExe,
    [string]$DshHome,
    [string]$DshProfile,
    [string]$WatchdogFile,
    [string]$WebLog,
    [string]$WatchdogLog,
    [int]$Interval = 3
)
$ErrorActionPreference = 'SilentlyContinue'
$lastWebTail = @()
$lastWatchdogTail = @()
$lastActivityTail = @()
$script:activeAction = $null
$script:activeStartedAt = $null
$script:lastProgressAt = $null

function Get-PortOpen([int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(300)
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

function Get-PortPid([int]$Port) {
    try {
        $lines = @(netstat -ano | Where-Object { $_ -match "TCP\s+.*:$Port\s+.*LISTENING" })
        foreach ($line in $lines) {
            $parts = ($line.Trim() -split '\s+')
            if ($parts.Count -lt 5) { continue }
            $addr = $parts[1]
            if ($addr -like '127.0.0.1:*' -or $addr -like '0.0.0.0:*' -or $addr -like '[::]:*' -or $addr -like '[::1]:*') {
                return [int]$parts[-1]
            }
        }
        if ($lines.Count -gt 0) {
            $parts = ($lines[0].Trim() -split '\s+')
            return [int]$parts[-1]
        }
    } catch {}
    return $null
}

function Get-WatchdogPids {
    $pids = @()
    $procs = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.ProcessId -eq $PID) { continue }
        if ($p.CommandLine -like '*dsh-watchdog.ps1*' -and
            $p.CommandLine -notlike '*ensure-dsh-watchdog.ps1*' -and
            $p.CommandLine -notlike '*dsh-control*' -and
            $p.CommandLine -notlike '*dsh-gui-poller.ps1*') {
            $pids += [int]$p.ProcessId
        }
    }
    return $pids
}

function Get-WslState {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wsl.exe'
        $psi.Arguments = '-l -v'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::Unicode
        $psi.StandardErrorEncoding = [System.Text.Encoding]::Unicode
        $p = [System.Diagnostics.Process]::Start($psi)
        if (-not $p.WaitForExit(2000)) {
            try { $p.Kill() } catch {}
            return 'Timeout'
        }
        $out = $p.StandardOutput.ReadToEnd()
        if ($out -match 'Running') { return 'Running' }
        if ($out -match 'Stopped') { return 'Stopped' }
        return 'Unknown'
    } catch {
        return 'Unknown'
    }
}

function Get-OllamaModels {
    try {
        $r = Invoke-RestMethod -Uri "http://127.0.0.1:$OllamaPort/api/tags" -TimeoutSec 1
        return (@($r.models | ForEach-Object { $_.name }) -join ', ')
    } catch {
        return ''
    }
}

function Get-HttpStatus {
    try {
        $r = Invoke-WebRequest -Uri $WebUrl -UseBasicParsing -TimeoutSec 1
        return "HTTP $($r.StatusCode)"
    } catch {
        return 'HTTP no response'
    }
}

function Get-ListenPid([int]$Port) {
    try {
        $lines = @(netstat -ano | Where-Object { $_ -match "TCP\s+.*:$Port\s+.*LISTENING" })
        foreach ($line in $lines) {
            $parts = ($line.Trim() -split '\s+')
            if ($parts.Count -lt 5) { continue }
            $addr = $parts[1]
            if ($addr -like '127.0.0.1:*' -or $addr -like '0.0.0.0:*' -or $addr -like '[::]:*' -or $addr -like '[::1]:*') {
                return [int]$parts[-1]
            }
        }
    } catch {}
    return $null
}

function Write-Activity([string]$msg) {
    try {
        $line = "$(Get-Date -Format 'HH:mm:ss')  $msg"
        [System.IO.File]::AppendAllText($ActivityFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch {}
}

function Start-WatchdogAction {
    $existing = @(Get-WatchdogPids)
    if ($existing.Count -gt 0) {
        Write-Activity "watchdog 已在运行 (PID $($existing -join ','))"
        return "watchdog already running (PID $($existing -join ','))"
    }
    Write-Activity '启动 watchdog ...'
    Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"$WatchdogFile" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    $now = @(Get-WatchdogPids)
    if ($now.Count -gt 0) {
        Write-Activity "watchdog 已启动 (PID $($now -join ','))"
        return "watchdog started (PID $($now -join ','))"
    }
    Write-Activity 'watchdog 启动失败'
    return 'watchdog start failed'
}

function Stop-DshAllAction {
    $ids = New-Object System.Collections.Generic.List[int]
    $cur = Get-ListenPid $WebPort
    for ($i = 0; $i -lt 6; $i++) {
        if (-not $cur) { break }
        if (-not $ids.Contains([int]$cur)) { $ids.Add([int]$cur) }
        $ci = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
        if (-not $ci) { break }
        $cur = $ci.ParentProcessId
    }
    Get-WatchdogPids | ForEach-Object {
        if (-not $ids.Contains([int]$_)) { $ids.Add([int]$_) }
    }
    if ($ids.Count -gt 0) { Write-Activity "正在停止 dsh 进程 (PID $($ids -join ',')) ..." }
    else { Write-Activity '没有检测到 dsh 进程' }
    foreach ($id in $ids) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
    if (Get-ListenPid $WebPort) {
        Write-Activity "停止完成，但端口 $WebPort 仍被占用"
        return 'stop done (dsh processes stopped, port still busy)'
    }
    Write-Activity "dsh 已停止 (端口 $WebPort 已释放)"
    return 'dsh stopped'
}

function Start-OllamaAction {
    if (Get-PortOpen $OllamaPort) {
        Write-Activity "Ollama 已在运行 (端口 $OllamaPort)"
        return 'Ollama already running'
    }
    $ollamaCmd = $null
    $g = Get-Command ollama -ErrorAction SilentlyContinue
    if ($g) { $ollamaCmd = $g.Source }
    elseif (Test-Path $OllamaExe) { $ollamaCmd = $OllamaExe }
    if ($ollamaCmd) {
        Write-Activity "启动 Ollama: $ollamaCmd serve (OLLAMA_HOST=127.0.0.1:$OllamaPort)"
        $env:OLLAMA_HOST = "127.0.0.1:$OllamaPort"
        Start-Process -FilePath $ollamaCmd -ArgumentList 'serve' -WindowStyle Hidden
        Remove-Item Env:OLLAMA_HOST -ErrorAction SilentlyContinue
        Write-Activity "Ollama 启动命令已发出 (端口 $OllamaPort)"
        return "Ollama start command sent ($ollamaCmd) on port $OllamaPort"
    }
    Write-Activity '未找到 ollama，请手动安装 (https://ollama.com)'
    return 'ollama not found, install from https://ollama.com'
}

function Get-ImageGenInfo {
    $port = 17821
    if (-not (Get-PortOpen $port)) {
        return @{ status = '未运行'; model = '' }
    }
    $model = ''
    try {
        $h = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
        if ($h -and $h.ok) { $model = $h.model }
    } catch {}
    return @{ status = '运行中'; model = $model }
}

function Start-ImageGenAction {
    $ig = Get-ImageGenInfo
    if ($ig.status -eq '运行中') {
        Write-Activity "生图服务已在运行 ($($ig.model))"
        return "image-gen running ($($ig.model))"
    }
    $py = 'F:\tools\image-gen\venv\Scripts\python.exe'
    $server = 'F:\tools\image-gen\server.py'
    if (-not (Test-Path $py) -or -not (Test-Path $server)) {
        Write-Activity '生图服务未安装（缺少 F:\tools\image-gen）'
        return 'image-gen not installed'
    }
    Write-Activity '启动生图服务 (17821, SDXL-Turbo) ... 首次加载模型约 10-30s'
    Start-Process -FilePath $py -ArgumentList @($server, '--port', '17821') -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(150)
    do {
        Start-Sleep -Milliseconds 1500
        $h = $null
        try { $h = Invoke-RestMethod -Uri "http://127.0.0.1:17821/health" -TimeoutSec 2 } catch {}
        if ($h -and $h.ok) {
            Write-Activity "生图服务就绪: $($h.model)"
            return "image-gen ready ($($h.model))"
        }
    } while ((Get-Date) -lt $deadline)
    Write-Activity '生图服务启动超时（查看 F:\tools\image-gen 是否完整）'
    return 'image-gen start timeout'
}

function Get-TailscaleInfo {
    $ts = 'F:\Tailscale\tailscale.exe'
    if (-not (Test-Path $ts)) {
        return @{ status = '未安装'; ip = ''; serve = '未安装' }
    }
    $statusText = & $ts status 2>&1 | Out-String
    if ($statusText -match 'Logged out|Log in at') {
        return @{ status = '未登录'; ip = ''; serve = '未启用' }
    }
    $ip = (& $ts ip -4 2>$null | Select-Object -First 1).Trim()
    $serveText = & $ts serve status 2>&1 | Out-String
    $serveUrl = ''
    if ($serveText -match 'https://([^\s]+)') { $serveUrl = $matches[1] }
    if (-not $serveUrl) { $serveUrl = '未启用' }
    return @{ status = "已连接 $ip"; ip = $ip; serve = $serveUrl }
}

function Repair-TailscaleAction {
    $ts = 'F:\Tailscale\tailscale.exe'
    if (-not (Test-Path $ts)) {
        Write-Activity 'Tailscale 未安装'
        return 'Tailscale not installed'
    }
    $serve = & $ts serve status 2>&1 | Out-String
    if ($serve -notmatch 'No serve config') {
        $url = ''
        if ($serve -match 'https://([^\s]+)') { $url = $matches[1] }
        Write-Activity "Tailscale Serve 已就绪: $url"
        return "Tailscale Serve OK: $url"
    }
    Write-Activity 'Tailscale Serve 无配置，尝试自动创建 serve --bg 3080 ...'
    $job = Start-Job -ScriptBlock {
        param($exe)
        & $exe serve --bg 3080 2>&1 | Out-String
    } -ArgumentList $ts
    if (Wait-Job $job -Timeout 10) {
        $out = Receive-Job $job
        Remove-Job $job -Force
        if ($out) { Write-Activity $out.Trim() }
        $serve = & $ts serve status 2>&1 | Out-String
        if ($serve -notmatch 'No serve config') {
            $url = ''
            if ($serve -match 'https://([^\s]+)') { $url = $matches[1] }
            Write-Activity "Tailscale Serve 修复成功: $url"
            return "Tailscale Serve fixed: $url"
        }
    }
    else {
        Stop-Job $job
        Remove-Job $job -Force
    }
    Write-Activity 'Tailscale Serve 未启用，请打开启用链接'
    return 'Tailscale Serve not enabled; open https://login.tailscale.com/f/serve?node=ny59qLPW6Y11CNTRL'
}

while ($true) {
    if (Test-Path $TriggerFile) {
        Remove-Item $TriggerFile -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path $CmdFile) {
        $raw = Get-Content -LiteralPath $CmdFile -Raw -Encoding UTF8
        Remove-Item -LiteralPath $CmdFile -Force -ErrorAction SilentlyContinue
        $cmd = $null
        try { $cmd = $raw | ConvertFrom-Json } catch {}
        if ($cmd) {
            $lines = @()
            if ($script:activeAction -and $cmd.action -in @('start','restart','stop')) {
                Write-Activity "忽略命令 $($cmd.action): 上一命令 $($script:activeAction) 仍在进行"
                $lines += "command ignored while $($script:activeAction) is running"
            } else {
                Write-Activity "==> 收到命令: $($cmd.action)"
                if ($cmd.action -in @('start','restart','stop')) {
                    $script:activeAction = $cmd.action
                    $script:activeStartedAt = Get-Date
                    $script:lastProgressAt = Get-Date
                }
                switch ($cmd.action) {
                    'start'  { $lines += Start-WatchdogAction }
                    'stop'   { $lines += Stop-DshAllAction }
                    'restart' {
                        $lines += Stop-DshAllAction
                        Start-Sleep -Seconds 1
                        $lines += Start-WatchdogAction
                    }
                    'ollama' { $lines += Start-OllamaAction }
                    'wsl' {
                        $out = wsl --shutdown 2>&1 | Out-String
                        if ($out.Trim()) { $lines += $out.Trim() }
                        $lines += 'WSL shut down; it will restart on next wsl_bash call'
                    }
                    'tailscale' { $lines += Repair-TailscaleAction }
                    'imagegen'  { $lines += Start-ImageGenAction }
                    default { $lines += "unknown command: $($cmd.action)" }
                }
                if ($cmd.action -eq 'ollama' -or $cmd.action -eq 'wsl' -or $cmd.action -eq 'tailscale' -or $cmd.action -eq 'imagegen') { $script:activeAction = $null }
            }
            $resultFile = $ResultPrefix + $cmd.id + '.json'
            $tmpResult = $resultFile + '.tmp'
            [System.IO.File]::WriteAllText($tmpResult, (@{ id = $cmd.id; lines = @($lines) } | ConvertTo-Json -Compress))
            Move-Item -LiteralPath $tmpResult -Destination $resultFile -Force
        }
    }
    $webUp = Get-PortOpen $WebPort
    $webPid = $null
    $http = ''
    if ($webUp) {
        $webPid = Get-PortPid $WebPort
        $http = Get-HttpStatus
    }
    $watchdogPids = Get-WatchdogPids
    $wsl = Get-WslState
    $ollamaUp = Get-PortOpen $OllamaPort
    $ollamaPid = $null
    $models = ''
    if ($ollamaUp) {
        $ollamaPid = Get-PortPid $OllamaPort
        $models = Get-OllamaModels
    }
    $webTail = @(Get-Content -LiteralPath $WebLog -Tail 12 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
    $webNew = @()
    foreach ($ln in $webTail) {
        if ($ln -notin $lastWebTail) { $webNew += $ln }
    }
    if ($webNew.Count -gt 0) { $lastWebTail = @($webTail) }
    $watchdogTail = @(Get-Content -LiteralPath $WatchdogLog -Tail 12 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
    $watchdogNew = @()
    foreach ($ln in $watchdogTail) {
        if ($ln -notin $lastWatchdogTail) { $watchdogNew += $ln }
    }
    if ($watchdogNew.Count -gt 0) { $lastWatchdogTail = @($watchdogTail) }
    $activityTail = @(Get-Content -LiteralPath $ActivityFile -Tail 12 -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ })
    $activityNew = @()
    foreach ($ln in $activityTail) {
        if ($ln -notin $lastActivityTail) { $activityNew += $ln }
    }
    if ($activityNew.Count -gt 0) { $lastActivityTail = @($activityTail) }

    if ($script:activeAction) {
        $elapsed = [int]((Get-Date) - $script:activeStartedAt).TotalSeconds
        if ($script:activeAction -eq 'stop') {
            if (-not $webUp) {
                Write-Activity "停止完成: 端口 $WebPort 已释放 (${elapsed}s)"
                $script:activeAction = $null
            } elseif ($elapsed -ge 60) {
                Write-Activity "停止超时: 端口 $WebPort 仍被占用 (${elapsed}s)"
                $script:activeAction = $null
            } elseif (((Get-Date) - $script:lastProgressAt).TotalSeconds -ge 5) {
                Write-Activity "正在等待端口 $WebPort 释放 ... (已 ${elapsed}s)"
                $script:lastProgressAt = Get-Date
            }
        } elseif ($script:activeAction -in @('start','restart')) {
            if ($webUp -and $http -like 'HTTP 200*') {
                Write-Activity "web 已就绪: $WebUrl ($http, ${elapsed}s)"
                $script:activeAction = $null
            } elseif ($elapsed -ge 240) {
                Write-Activity "web 就绪等待超时 (${elapsed}s)，watchdog 仍在后台探测"
                $script:activeAction = $null
            } elseif (((Get-Date) - $script:lastProgressAt).TotalSeconds -ge 5) {
                Write-Activity "正在等待 web 就绪 ... (已 ${elapsed}s, watchdog 后台探测中)"
                $script:lastProgressAt = Get-Date
            }
        }
    }
    $tsInfo = Get-TailscaleInfo
    $igInfo = Get-ImageGenInfo
    $snap = [ordered]@{
        time = Get-Date -Format 'HH:mm:ss'
        webUp = $webUp
        http = $http
        webPid = $webPid
        watchdogPids = ($watchdogPids -join ',')
        wsl = $wsl
        ollamaUp = $ollamaUp
        ollamaPid = $ollamaPid
        models = $models
        dshHome = Test-Path $DshHome
        dshProfile = Test-Path $DshProfile
        tailscale = $tsInfo.status
        tailscaleIp = $tsInfo.ip
        tailscaleServe = $tsInfo.serve
        imagegen = $igInfo.status
        imagegenModel = $igInfo.model
        webLogTail = @($webNew)
        watchdogLogTail = @($watchdogNew)
        activityLogTail = @($activityNew)
    }
    try {
        $tmpFile = $StatusFile + '.tmp'
        [System.IO.File]::WriteAllText($tmpFile, ($snap | ConvertTo-Json -Compress))
        Move-Item -LiteralPath $tmpFile -Destination $StatusFile -Force
    } catch {}
    Start-Sleep -Seconds $Interval
}
'@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}


# ---- 自提权 ----
if (-not (Test-Admin)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PSCommandPath`"")
    Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -WorkingDirectory (Split-Path $PSCommandPath)
    exit
}

# ---- UI ----
[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = 'dsh 控制台'
$form.ClientSize = New-Object System.Drawing.Size(900, 860)
$form.MinimumSize = New-Object System.Drawing.Size(760, 720)
$form.StartPosition = 'CenterScreen'
$form.KeyPreview = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(26, 30, 42)
if (Test-Path $IconFile) { $form.Icon = New-Object System.Drawing.Icon($IconFile) }

$statusLabels = @{}

# 顶部横幅: 只引用本地图片路径，不做任何读取分析。
$Banner = New-Object System.Windows.Forms.PictureBox
$Banner.Dock = 'Top'
$Banner.Height = 280
$Banner.SizeMode = 'Zoom'
$Banner.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 36)
try {
    if (Test-Path $ImageFile) { $Banner.Image = [System.Drawing.Image]::FromFile($ImageFile) }
} catch {
    $Banner.Image = $null
}

# 状态面板
$statusGroup = New-Object System.Windows.Forms.GroupBox
$statusGroup.Text = '状态'
$statusGroup.Dock = 'Top'
$statusGroup.Height = 190
$statusGroup.Padding = New-Object System.Windows.Forms.Padding(8)
$statusGroup.ForeColor = [System.Drawing.Color]::WhiteSmoke
$statusGroup.BackColor = [System.Drawing.Color]::FromArgb(32, 38, 52)

$tbl = New-Object System.Windows.Forms.TableLayoutPanel
$tbl.Dock = 'Fill'
$tbl.ColumnCount = 2
$tbl.RowCount = 6
$tbl.BackColor = [System.Drawing.Color]::FromArgb(32, 38, 52)
$tbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 90))) | Out-Null
$tbl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
for ($i = 0; $i -lt 7; $i++) { $tbl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 14.28))) | Out-Null }
$statusGroup.Controls.Add($tbl)

$nameFont = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold)
$valFont  = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$names = @('web', 'watchdog', 'WSL', 'ollama', 'dsh home', 'Tailscale', '生图')
for ($i = 0; $i -lt $names.Count; $i++) {
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $names[$i]
    $lbl.Font = $nameFont
    $lbl.Dock = 'Fill'
    $lbl.TextAlign = 'MiddleLeft'
    $lbl.ForeColor = [System.Drawing.Color]::WhiteSmoke
    $tbl.Controls.Add($lbl, 0, $i)

    $val = New-Object System.Windows.Forms.Label
    $val.Text = '-'
    $val.Font = $valFont
    $val.Dock = 'Fill'
    $val.TextAlign = 'MiddleLeft'
    $val.ForeColor = [System.Drawing.Color]::WhiteSmoke
    $tbl.Controls.Add($val, 1, $i)
    $statusLabels[$names[$i]] = $val
}

function Set-StatusText($key, $text, $color) {
    $lbl = $statusLabels[$key]
    $lbl.Text = $text
    $lbl.ForeColor = $color
}

function Update-Status {
    param([switch]$Force)
    if ($Force) {
        New-Item -ItemType File -Path $TriggerFile -Force | Out-Null
    }
    try {
        if (-not (Test-Path $StatusFile)) {
            $refreshLabel.Text = '状态后台线程启动中...'
            return
        }
        $raw = Get-Content -LiteralPath $StatusFile -Raw -Encoding UTF8
        if (-not $raw -or $raw -eq $lastStatusRaw) { return }
        $script:lastStatusRaw = $raw
        $snap = $raw | ConvertFrom-Json
        if (-not $snap) { return }

        if ($null -ne $snap.activityLogTail) { foreach ($ln in @($snap.activityLogTail)) { if ($ln) { Add-Log $ln } } }

        if (-not $script:logTailReady) {
            if ($null -ne $snap.webLogTail -or $null -ne $snap.watchdogLogTail) { $script:logTailReady = $true }
        }
        else {
            if ($null -ne $snap.webLogTail) { foreach ($ln in @($snap.webLogTail)) { if ($ln) { Add-Log "[web] $ln" } } }
            if ($null -ne $snap.watchdogLogTail) { foreach ($ln in @($snap.watchdogLogTail)) { if ($ln) { Add-Log "[watchdog] $ln" } } }
        }

        if ($snap.webUp) {
            $text = "运行中 ($($snap.http)"
            if ($snap.webPid) { $text += ", PID $($snap.webPid)" }
            $text += ')'
            Set-StatusText 'web' $text ([System.Drawing.Color]::ForestGreen)
        } else {
            Set-StatusText 'web' '未运行' ([System.Drawing.Color]::Firebrick)
        }

        if ($snap.watchdogPids) {
            Set-StatusText 'watchdog' "运行中 (PID $($snap.watchdogPids))" ([System.Drawing.Color]::ForestGreen)
        } else {
            Set-StatusText 'watchdog' '未运行' ([System.Drawing.Color]::Firebrick)
        }

        if ($snap.wsl -eq 'Running') { Set-StatusText 'WSL' 'Running (虚拟 linux)' ([System.Drawing.Color]::ForestGreen) }
        else                          { Set-StatusText 'WSL' "$($snap.wsl) (虚拟 linux)" ([System.Drawing.Color]::DarkOrange) }

        if ($snap.ollamaUp) {
            if ($snap.models) { Set-StatusText 'ollama' "运行中 (模型: $($snap.models))" ([System.Drawing.Color]::ForestGreen) }
            else               { Set-StatusText 'ollama' '运行中 (dsh-vision 可用)' ([System.Drawing.Color]::ForestGreen) }
        } else {
            Set-StatusText 'ollama' '未运行 (dsh-vision 不可用)' ([System.Drawing.Color]::DarkOrange)
        }

        if ($snap.dshHome) {
            if ($snap.dshProfile) { Set-StatusText 'dsh home' "$DshHome (web profile 已配置)" ([System.Drawing.Color]::ForestGreen) }
            else                   { Set-StatusText 'dsh home' "$DshHome (web profile 缺失)" ([System.Drawing.Color]::DarkOrange) }
        } else {
            Set-StatusText 'dsh home' "$DshHome (缺失)" ([System.Drawing.Color]::Firebrick)
        }

        if ($snap.tailscale) {
            if ($snap.tailscale -like '已连接*') {
                $tsText = $snap.tailscale
                if ($snap.tailscaleServe -and $snap.tailscaleServe -ne '未启用') { $tsText += " | $($snap.tailscaleServe)" }
                Set-StatusText 'Tailscale' $tsText ([System.Drawing.Color]::ForestGreen)
            } elseif ($snap.tailscale -eq '未登录') {
                Set-StatusText 'Tailscale' '未登录' ([System.Drawing.Color]::DarkOrange)
            } elseif ($snap.tailscale -eq '未安装') {
                Set-StatusText 'Tailscale' '未安装' ([System.Drawing.Color]::Firebrick)
            } else {
                Set-StatusText 'Tailscale' $snap.tailscale ([System.Drawing.Color]::DarkOrange)
            }
        } else {
            Set-StatusText 'Tailscale' '未知' ([System.Drawing.Color]::DarkOrange)
        }

        if ($snap.imagegen -eq '运行中') {
            if ($snap.imagegenModel) { Set-StatusText '生图' "运行中 (模型: $($snap.imagegenModel))" ([System.Drawing.Color]::ForestGreen) }
            else                     { Set-StatusText '生图' '运行中' ([System.Drawing.Color]::ForestGreen) }
        } elseif ($snap.imagegen) {
            Set-StatusText '生图' "$($snap.imagegen) (generate_image 不可用)" ([System.Drawing.Color]::DarkOrange)
        } else {
            Set-StatusText '生图' '未知' ([System.Drawing.Color]::DarkOrange)
        }

        $refreshLabel.Text = "最后刷新: $($snap.time) | ${WebPort}: $($snap.webPid) | ${OllamaPort}: $($snap.ollamaPid)"
    } catch {
        $refreshLabel.Text = "状态读取失败: $($_.Exception.Message)"
    }
}

function Start-StatusPoller {
    try {
        if ($pollerProcess -and -not $pollerProcess.HasExited) { return }
    } catch {}
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*dsh-gui-poller.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Remove-Item $StatusFile, $TriggerFile, $ActivityFile -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $PollerFile -Value $PollerScript -Encoding UTF8
    $argList = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$PollerFile`"",
        '-StatusFile', "`"$StatusFile`"",
        '-TriggerFile', "`"$TriggerFile`"",
        '-CmdFile', "`"$CmdFile`"",
        '-ResultPrefix', "`"$ResultPrefix`"",
        '-ActivityFile', "`"$ActivityFile`"",
        '-WebUrl', "`"$WebUrl`"",
        '-WebPort', "$WebPort",
        '-OllamaPort', "$OllamaPort",
        '-OllamaExe', "`"$OllamaExe`"",
        '-DshHome', "`"$DshHome`"",
        '-DshProfile', "`"$DshProfile`"",
        '-WatchdogFile', "`"$WatchdogFile`"",
        '-WebLog', "`"$WebLog`"",
        '-WatchdogLog', "`"$WatchdogLog`"",
        '-Interval', '3'
    )
    $script:pollerProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Hidden -PassThru
}

function Send-Action($action, $label) {
    $id = [guid]::NewGuid().ToString('N')
    $cmd = @{ action = $action; id = $id } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($CmdFile, $cmd)
    Add-Log "==> $label 命令已发送"
}

function Read-ActionResults {
    $files = Get-ChildItem -LiteralPath $env:TEMP -Filter 'dsh-gui-result-*.json' -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        try {
            $res = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($line in @($res.lines)) {
                if ($line) { Add-Log $line }
            }
        } catch {}
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    }
}

# 按钮面板
$btnPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$btnPanel.Dock = 'Top'
$btnPanel.Height = 126
$btnPanel.Padding = New-Object System.Windows.Forms.Padding(10, 10, 10, 4)
$btnPanel.AutoScroll = $true
$btnPanel.BackColor = [System.Drawing.Color]::FromArgb(26, 30, 42)
$form.Controls.Add($btnPanel)
$form.Controls.Add($statusGroup)

$tip = New-Object System.Windows.Forms.ToolTip

function New-ActionButton($text, $width, $script, $tipText = '') {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Width = $width
    $b.Height = 30
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 6, 6)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(70, 80, 100)
    $b.BackColor = [System.Drawing.Color]::FromArgb(42, 48, 64)
    $b.ForeColor = [System.Drawing.Color]::WhiteSmoke
    $b.Add_Click($script)
    if ($tipText) { $tip.SetToolTip($b, $tipText) }
    $btnPanel.Controls.Add($b)
    return $b
}

New-ActionButton '启动' 76 {
    Send-Action 'start' '启动 dsh'
} '启动 watchdog，快速探测 180 秒' | Out-Null

New-ActionButton '重启' 76 {
    Send-Action 'restart' '重启 dsh'
} '先停止端口 3080 进程链，再启动 watchdog' | Out-Null

New-ActionButton '远程重启' 96 {
    $ts = 'F:\Tailscale\tailscale.exe'
    if (Test-Path $ts) {
        $serve = & $ts serve status 2>&1 | Out-String
        if ($serve -match 'No serve config') {
            Add-Log 'Tailscale Serve 无配置，尝试自动创建 serve --bg 3080 ...'
            $job = Start-Job -ScriptBlock {
                param($exe)
                & $exe serve --bg 3080 2>&1 | Out-String
            } -ArgumentList $ts
            if (Wait-Job $job -Timeout 10) {
                $out = Receive-Job $job
                Remove-Job $job -Force
                if ($out) { Add-Log $out.Trim() }
                $serve = & $ts serve status 2>&1 | Out-String
                if ($serve -match 'No serve config') {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Tailscale Serve 仍未创建成功。`n`n请先打开下面的链接启用：`nhttps://login.tailscale.com/f/serve?node=ny59qLPW6Y11CNTRL`n`n启用后再点远程重启。",
                        'Tailscale 远程模式',
                        'OK',
                        'Information'
                    ) | Out-Null
                    return
                }
            }
            else {
                Stop-Job $job
                Remove-Job $job -Force
                [System.Windows.Forms.MessageBox]::Show(
                    "Tailscale Serve 未启用或超时。`n`n请先打开下面的链接启用：`nhttps://login.tailscale.com/f/serve?node=ny59qLPW6Y11CNTRL`n`n启用后再点远程重启。",
                    'Tailscale 远程模式',
                    'OK',
                    'Information'
                ) | Out-Null
                return
            }
        }
    }
    Send-Action 'restart' '重启 dsh (Tailscale 远程模式)'
} '需要先启用 Tailscale Serve；启用后重启 dsh 并自动配置 trusted-host，供 Android/iPad 访问' | Out-Null

New-ActionButton 'Tailscale修复' 96 {
    Send-Action 'tailscale' 'Tailscale 修复'
} '检查/修复 Tailscale Serve：自动执行 serve --bg 3080，并显示状态' | Out-Null

New-ActionButton '生图服务' 84 {
    Send-Action 'imagegen' '生图服务'
} '启动/检测本地生图服务 (SDXL-Turbo, 17821)，供 generate_image 工具使用；首次加载模型约 10-30s' | Out-Null

New-ActionButton '停止' 76 {
    Send-Action 'stop' '停止 dsh'
} '停止 dsh 及 watchdog' | Out-Null

New-ActionButton '打开 Web UI' 104 {
    Start-Process $WebUrl
    Add-Log "==> 已打开 $WebUrl"
} '浏览器打开 http://127.0.0.1:3080' | Out-Null

New-ActionButton '查看日志' 84 {
    Add-Log '==> 最近日志'
    foreach ($f in @($WatchdogLog, $WebLog)) {
        if (Test-Path $f) {
            Add-Log "--- $(Split-Path $f -Leaf) ---"
            Get-Content $f -Tail 8 -Encoding UTF8 | ForEach-Object { $logBox.AppendText("$_`r`n") }
        }
    }
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
} '显示 watchdog 与 dsh-web 最近 8 行' | Out-Null

New-ActionButton 'Ollama' 76 {
    Send-Action 'ollama' 'Ollama'
} '以 OLLAMA_HOST=127.0.0.1:11810 启动，PATH 优先，回退便携版' | Out-Null

New-ActionButton '重启 WSL' 84 {
    $ans = [System.Windows.Forms.MessageBox]::Show('确认重启 WSL (虚拟 linux)? 运行中的 Linux 进程会被终止。', '重启 WSL', 'YesNo', 'Warning')
    if ($ans -eq 'Yes') {
        Send-Action 'wsl' '重启 WSL'
    }
} '关闭当前 WSL 虚拟机' | Out-Null

New-ActionButton '刷新' 72 {
    Update-Status -Force
    Add-Log '状态已刷新 (F5)'
} '刷新状态 (F5)' | Out-Null

New-ActionButton '清空日志' 84 {
    $logBox.Clear()
    Add-Log '日志已清空 (Ctrl+L)'
} '清空日志输出 (Ctrl+L)' | Out-Null

New-ActionButton '配置目录' 84 {
    if (Test-Path $DshHome) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$DshHome`""
        Add-Log "==> 已打开 $DshHome"
    } else {
        Add-Log "dsh home 不存在: $DshHome"
    }
} "打开 $DshHome" | Out-Null

New-ActionButton '复制诊断' 84 {
    $lines = @(
        "dsh 控制台诊断 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "web: $($statusLabels['web'].Text)",
        "watchdog: $($statusLabels['watchdog'].Text)",
        "WSL: $($statusLabels['WSL'].Text)",
        "ollama: $($statusLabels['ollama'].Text)",
        "dsh home: $($statusLabels['dsh home'].Text)",
        "web: $WebUrl | log: $WebLog",
        "watchdog log: $WatchdogLog",
        "profile: $DshProfile"
    )
    [System.Windows.Forms.Clipboard]::SetText(($lines -join "`r`n"))
    Add-Log '诊断信息已复制到剪贴板'
} '复制当前状态与关键路径，便于反馈问题' | Out-Null

New-ActionButton 'web profile' 92 {
    if (Test-Path $DshProfile) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$DshProfile`""
        Add-Log "==> 已打开 $DshProfile"
    } else {
        Add-Log "web profile 不存在: $DshProfile"
    }
} "打开 $DshProfile" | Out-Null

# 日志面板
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = '日志 / 输出'
$logGroup.Dock = 'Fill'
$logGroup.Padding = New-Object System.Windows.Forms.Padding(8)
$logGroup.ForeColor = [System.Drawing.Color]::WhiteSmoke
$logGroup.BackColor = [System.Drawing.Color]::FromArgb(32, 38, 52)
$form.Controls.Add($logGroup)

$logBox = New-Object System.Windows.Forms.RichTextBox
$logBox.Dock = 'Fill'
$logBox.ReadOnly = $true
$logBox.BackColor = [System.Drawing.Color]::FromArgb(24, 26, 36)
$logBox.ForeColor = [System.Drawing.Color]::WhiteSmoke
$logBox.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$logBox.BorderStyle = 'None'
$logGroup.Controls.Add($logBox)

$logMenu = New-Object System.Windows.Forms.ContextMenuStrip
$copyItem = New-Object System.Windows.Forms.ToolStripMenuItem('复制选中')
$copyItem.Add_Click({
    if ($logBox.SelectionLength -gt 0) { $logBox.Copy() }
    else { [System.Windows.Forms.Clipboard]::SetText($logBox.Text) }
})
$selectItem = New-Object System.Windows.Forms.ToolStripMenuItem('全选')
$selectItem.Add_Click({ $logBox.SelectAll() })
$clearItem = New-Object System.Windows.Forms.ToolStripMenuItem('清空')
$clearItem.Add_Click({ $logBox.Clear() })
$logMenu.Items.AddRange(@($copyItem, $selectItem, $clearItem)) | Out-Null
$logBox.ContextMenuStrip = $logMenu

function Add-Log($msg) {
    if ($logBox.TextLength -gt 300000) {
        $logBox.Select(0, 100000)
        $logBox.SelectedText = ''
    }
    $logBox.AppendText("$(Get-Date -Format 'HH:mm:ss')  $msg`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
}

# 底部状态栏
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.Dock = 'Bottom'
$statusStrip.BackColor = [System.Drawing.Color]::FromArgb(20, 24, 36)
$statusStrip.ForeColor = [System.Drawing.Color]::WhiteSmoke
$refreshLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$refreshLabel.Text = '最后刷新: -'
$refreshLabel.ForeColor = [System.Drawing.Color]::WhiteSmoke
$statusStrip.Items.Add($refreshLabel) | Out-Null
$form.Controls.Add($statusStrip)
$form.Controls.Add($Banner)

# 让日志区最后参与停靠计算，避免第一行被上方按钮/状态面板盖住。
$form.Controls.SetChildIndex($logGroup, 0)

# 定时刷新状态
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({ Update-Status; Read-ActionResults })
$timer.Start()

# 快捷键
$form.Add_KeyDown({
    param($s, $e)
    if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F5) {
        Update-Status -Force
        Add-Log '状态已刷新 (F5)'
        $e.SuppressKeyPress = $true
    } elseif ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::L) {
        $logBox.Clear()
        Add-Log '日志已清空 (Ctrl+L)'
        $e.SuppressKeyPress = $true
    }
})

# 自检模式: 3 秒后自动关闭
if ($args -contains '-SmokeTest') {
    $smoke = New-Object System.Windows.Forms.Timer
    $smoke.Interval = 3000
    $smoke.Add_Tick({ $form.Close() })
    $smoke.Start()
}

$form.Add_Shown({ Start-StatusPoller; Update-Status -Force; Add-Log 'dsh 控制台已就绪' })
$form.Add_FormClosed({
    try {
        if ($script:pollerProcess -and -not $script:pollerProcess.HasExited) {
            Stop-Process -Id $script:pollerProcess.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
    Get-ChildItem -LiteralPath $env:TEMP -Filter 'dsh-gui-result-*.json' -ErrorAction SilentlyContinue | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    Remove-Item $StatusFile, $TriggerFile, $PollerFile, $CmdFile, $ActivityFile -Force -ErrorAction SilentlyContinue
})

try {
    [System.Windows.Forms.Application]::Run($form)
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.ToString(), 'dsh 控制台错误') | Out-Null
}
