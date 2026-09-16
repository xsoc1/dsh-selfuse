param(
    [string]$StatusFile,
    [string]$TriggerFile,
    [string]$CmdFile,
    [string]$ResultPrefix,
    [string]$ActivityFile,
    [string]$WebUrl,
    [int]$WebPort,
    [string]$DshHome,
    [string]$DshProfile,
    [string]$WatchdogFile,
    [string]$WebLog,
    [string]$WatchdogLog,
    [string]$HarnessRoot,
    [string]$PollerPidFile,
    [int]$Interval = 3
)
$ErrorActionPreference = 'SilentlyContinue'
try { [System.IO.File]::WriteAllText($PollerPidFile, "$PID") } catch {}

$lastWebTail = @()
$lastWatchdogTail = @()
$lastActivityTail = @()
$script:activeAction = $null
$script:activeStartedAt = $null
$script:lastProgressAt = $null
$script:cachedWebUrl = $null
$script:cachedWsl = 'Unknown'
$script:lastWslCheckAt = [datetime]::MinValue
$script:cachedTsInfo = $null
$script:lastTsCheckAt = [datetime]::MinValue
$probeFile = Join-Path $PSScriptRoot 'dsh-gui-probes.ps1'
if (-not (Test-Path -LiteralPath $probeFile)) {
    $probeFile = Join-Path $HarnessRoot 'packages\selfuse\control-gui\dsh-gui-probes.ps1'
}
$script:probesAvailable = Test-Path -LiteralPath $probeFile
if ($script:probesAvailable) { . $probeFile }

function Get-PortOpen([int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(150)
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

function Test-WebReady([bool]$PortOpen, [string]$HttpStatus) {
    return ($PortOpen -and $HttpStatus -eq 'HTTP 200')
}

function Resolve-TailscaleExe {
    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += (Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe')
    }
    $candidates += 'F:\Tailscale\tailscale.exe'
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command -and $command.Source) { $candidates += $command.Source }
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Invoke-TailscaleCommand([string]$Path, [string[]]$CommandArgs) {
    $process = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $Path
        $psi.Arguments = ($CommandArgs -join ' ')
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(2500)) {
            try { $process.Kill() } catch {}
            return @{ ok = $false; output = '' }
        }
        $output = $outputTask.Result
        $null = $errorTask.Result
        return @{ ok = ($process.ExitCode -eq 0); output = $output }
    } catch {
        return @{ ok = $false; output = '' }
    } finally {
        if ($process) { $process.Dispose() }
    }
}

function Get-PortPid([int]$Port) {
    try {
        $lines = @(netstat -ano -p tcp | Where-Object { $_ -match "TCP\s+.*:$Port\s+.*LISTENING" })
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
    $pidFile = Join-Path $HarnessRoot 'dsh-watchdog.pid'
    if (Test-Path $pidFile) {
        $rawPid = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($rawPid -match '^\d+$') {
            try {
                $wp = [System.Diagnostics.Process]::GetProcessById([int]$rawPid)
                if ($wp -and -not $wp.HasExited -and ($wp.ProcessName -like '*powershell*' -or $wp.ProcessName -like '*pwsh*')) {
                    return @([int]$rawPid)
                }
            } catch {}
        }
    }
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

function Get-WslState([bool]$WebIsUp, [switch]$Force) {
    if ($WebIsUp) {
        $script:cachedWsl = 'Running'
        return 'Running'
    }
    if (-not $Force -and ((Get-Date) - $script:lastWslCheckAt).TotalSeconds -lt 25 -and $script:cachedWsl -ne 'Unknown') {
        return $script:cachedWsl
    }
    $script:lastWslCheckAt = Get-Date
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
        if (-not $p.WaitForExit(1500)) {
            try { $p.Kill() } catch {}
            return 'Timeout'
        }
        $out = $p.StandardOutput.ReadToEnd()
        if ($out -match 'Running') { $script:cachedWsl = 'Running'; return 'Running' }
        if ($out -match 'Stopped') { $script:cachedWsl = 'Stopped'; return 'Stopped' }
        return 'Unknown'
    } catch {
        return 'Unknown'
    }
}

function Get-DshWebUrl([switch]$Force) {
    if (-not $Force -and $script:cachedWebUrl) { return $script:cachedWebUrl }
    if (Test-Path $WebLog) {
        try {
            $line = Get-Content -LiteralPath $WebLog -Tail 80 -Encoding UTF8 -ErrorAction SilentlyContinue |
                Select-String -Pattern 'http://127\.0\.0\.1:3080/\?token=[A-Za-z0-9_-]+' |
                Select-Object -Last 1
            if ($line -and $line.Matches.Count -gt 0) {
                $script:cachedWebUrl = $line.Matches[0].Value
                return $script:cachedWebUrl
            }
        } catch {}
    }
    return $WebUrl
}

function Get-HttpStatus {
    try {
        $r = Invoke-WebRequest -Uri (Get-DshWebUrl) -UseBasicParsing -TimeoutSec 1
        return "HTTP $($r.StatusCode)"
    } catch {
        $script:cachedWebUrl = $null
        try {
            $r = Invoke-WebRequest -Uri $WebUrl -UseBasicParsing -TimeoutSec 1
            return "HTTP $($r.StatusCode)"
        } catch {
            return 'HTTP no response'
        }
    }
}

function Get-ListenPid([int]$Port) {
    try {
        $lines = @(netstat -ano -p tcp | Where-Object { $_ -match "TCP\s+.*:$Port\s+.*LISTENING" })
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
    $stopFlag = Join-Path $HarnessRoot 'dsh-manual-stop.flag'
    Remove-Item $stopFlag -Force -ErrorAction SilentlyContinue
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
    $stopFlag = Join-Path $HarnessRoot 'dsh-manual-stop.flag'
    try { [System.IO.File]::WriteAllText($stopFlag, "stopped at $(Get-Date)") } catch {}

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
    & wsl.exe -d Ubuntu -e bash -lc "pkill -f 'apps/cli/src/bin.ts' || true" 2>&1 | Out-Null
    & wsl.exe -d Ubuntu -e bash -lc "pkill -f 'dsh-watchdog.ps1' || true" 2>&1 | Out-Null
    & wsl.exe -d Ubuntu -e bash -lc "pkill -f 'run-dsh-web.ps1' || true" 2>&1 | Out-Null
    Remove-Item (Join-Path $HarnessRoot 'dsh-watchdog.pid') -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $HarnessRoot 'dsh-watchdog.heartbeat') -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (Get-ListenPid $WebPort) {
        Write-Activity "停止完成，但端口 $WebPort 仍被占用"
        return 'stop done (dsh processes stopped, port still busy)'
    }
    Write-Activity "dsh 已停止 (端口 $WebPort 已释放)"
    return 'dsh stopped'
}

function Get-TailscaleInfo([switch]$Force) {
    $ts = Resolve-TailscaleExe
    if (-not $ts) {
        $script:cachedTsInfo = @{ status = '未安装'; ip = ''; serve = '未安装' }
        return $script:cachedTsInfo
    }
    $service = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
    if (-not $service -or $service.Status -ne 'Running') {
        $script:cachedTsInfo = @{ status = '未运行'; ip = ''; serve = '未启用' }
        return $script:cachedTsInfo
    }
    if (-not $Force -and $script:cachedTsInfo -and ((Get-Date) - $script:lastTsCheckAt).TotalSeconds -lt 6) {
        return $script:cachedTsInfo
    }
    $script:lastTsCheckAt = Get-Date
    $result = Invoke-TailscaleCommand $ts @('status', '--json')
    if (-not $result.ok) {
        $script:cachedTsInfo = @{ status = '状态不可用'; ip = ''; serve = '未知' }
        return $script:cachedTsInfo
    }
    try {
        $state = $result.output | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $script:cachedTsInfo = @{ status = '状态不可用'; ip = ''; serve = '未知' }
        return $script:cachedTsInfo
    }
    if ($state.BackendState -match '^(NeedsLogin|NeedsMachineAuth|NeedsAuth)$') {
        $script:cachedTsInfo = @{ status = '未登录'; ip = ''; serve = '未启用' }
        return $script:cachedTsInfo
    }
    if ($state.BackendState -ne 'Running') {
        $script:cachedTsInfo = @{ status = '未连接'; ip = ''; serve = '未启用' }
        return $script:cachedTsInfo
    }
    $ip = @($state.Self.TailscaleIPs) | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1
    if (-not $ip) {
        $script:cachedTsInfo = @{ status = '连接中'; ip = ''; serve = '未知' }
        return $script:cachedTsInfo
    }
    $serveResult = Invoke-TailscaleCommand $ts @('serve', 'status')
    $serveUrl = if ($serveResult.ok -and $serveResult.output -match 'https://([^\s]+)') { $matches[1] } elseif ($serveResult.ok) { '未启用' } else { '未知' }
    $script:cachedTsInfo = @{ status = "已连接 $ip"; ip = $ip; serve = $serveUrl }
    return $script:cachedTsInfo
}

while ($true) {
    $isForced = $false
    if (Test-Path $TriggerFile) {
        Remove-Item $TriggerFile -Force -ErrorAction SilentlyContinue
        $isForced = $true
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
                    'remote-health' {
                        if ($script:probesAvailable) { $lines += @(Get-RemoteHealthReport $WebPort $WebLog) }
                        else { $lines += '远程检查脚本缺失' }
                    }
                    'update-preflight' {
                        if ($script:probesAvailable) { $lines += @(Get-UpdatePreflightReport) }
                        else { $lines += '更新预检脚本缺失' }
                    }
                    default { $lines += "unknown command: $($cmd.action)" }
                }
            }
            $resultFile = $ResultPrefix + $cmd.id + '.json'
            $tmpResult = $resultFile + '.tmp'
            [System.IO.File]::WriteAllText($tmpResult, (@{ id = $cmd.id; lines = @($lines) } | ConvertTo-Json -Compress))
            Move-Item -LiteralPath $tmpResult -Destination $resultFile -Force
        }
    }
    $webPortOpen = Get-PortOpen $WebPort
    $webPid = $null
    $http = ''
    if ($webPortOpen) {
        $webPid = Get-PortPid $WebPort
        $http = Get-HttpStatus
    }
    $webUp = Test-WebReady $webPortOpen $http
    $watchdogPids = Get-WatchdogPids
    $wsl = Get-WslState $webUp -Force:$isForced
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
            if (-not $webPortOpen) {
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
                Write-Activity "web 已就绪: $(Get-DshWebUrl) ($http, ${elapsed}s)"
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
    $tsInfo = Get-TailscaleInfo -Force:$isForced
    $snap = [ordered]@{
        time = Get-Date -Format 'HH:mm:ss'
        webUp = $webUp
        webPortOpen = $webPortOpen
        http = $http
        webPid = $webPid
        watchdogPids = ($watchdogPids -join ',')
        wsl = $wsl
        dshHome = Test-Path $DshHome
        dshProfile = Test-Path $DshProfile
        tailscale = $tsInfo.status
        tailscaleIp = $tsInfo.ip
        tailscaleServe = $tsInfo.serve
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
