$ErrorActionPreference = "Continue"
$HarnessRoot = $PSScriptRoot
if (-not (Test-Path (Join-Path $HarnessRoot "package.json"))) {
    if (Test-Path 'F:\tools\deepseek-harness\package.json') {
        $HarnessRoot = 'F:\tools\deepseek-harness'
    } elseif ($env:DSH_ROOT -and (Test-Path (Join-Path $env:DSH_ROOT "package.json"))) {
        $HarnessRoot = $env:DSH_ROOT
    } else {
        $HarnessRoot = '\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness'
    }
}
$log = "$HarnessRoot\dsh-watchdog.log"
$runner = "$HarnessRoot\run-dsh-web.ps1"
$heartbeat = "$HarnessRoot\dsh-watchdog.heartbeat"
$WebLog = "$HarnessRoot\dsh-web.log"
$probe = "http://127.0.0.1:3080"
$probeTimeoutSec = 3
$webPort = 3080
# Boot probing instead of a blind grace sleep: poll every few seconds until
# the server answers, restart only after a real boot timeout.
$bootTimeoutSec = 180
$bootProbeIntervalSec = 3
$pollIntervalSec = 10
$consecutiveFailLimit = 3

function Write-Log([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg"
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

$PidFile = "$HarnessRoot\dsh-watchdog.pid"
$StopFlag = "$HarnessRoot\dsh-manual-stop.flag"
Remove-Item $StopFlag -Force -ErrorAction SilentlyContinue

function Write-Heartbeat {
    try {
        [System.IO.File]::WriteAllText($heartbeat, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $PID")
        [System.IO.File]::WriteAllText($PidFile, "$PID")
    } catch {}
}

function Get-DshWebUrl {
    $candidates = @($WebLog, 'F:\tools\deepseek-harness\dsh-web.log', '\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness\dsh-web.log')
    foreach ($candidate in $candidates) {
        try {
            if (Test-Path $candidate) {
                $line = Get-Content -LiteralPath $candidate -Tail 300 -Encoding UTF8 -ErrorAction SilentlyContinue |
                    Select-String -Pattern 'http://127\.0\.0\.1:3080/\?token=[A-Za-z0-9_-]+' |
                    Select-Object -Last 1
                if ($line -and $line.Matches.Count -gt 0) { return $line.Matches[0].Value }
            }
        } catch {}
    }
    return $WebUrl
}

function Test-DshAlive {
    try {
        $r = Invoke-WebRequest -Uri (Get-DshWebUrl) -UseBasicParsing -TimeoutSec $probeTimeoutSec
        return ($r.StatusCode -eq 200)
    }
    catch {
        return $false
    }
}

function Start-DshWeb {
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$runner -WindowStyle Hidden
}

function Test-DshStarting {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe' -or $_.Name -eq 'node.exe' -or $_.Name -eq 'cmd.exe') -and
            ($_.CommandLine -like '*run-dsh-web.ps1*' -or $_.CommandLine -like '*apps/cli/src/bin.ts*')
        }
    return @($procs).Count -gt 0
}

$wslDistro = "Ubuntu"
$wslStartTimeoutSec = 20
$wslEnsureIntervalSec = 60

function Test-WslGateway {
    $nic = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "vEthernet (WSL (Hyper-V firewall))" -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "172.*" } | Select-Object -First 1
    return ($null -ne $nic)
}

function Start-DshWsl([string]$Distro, [int]$TimeoutSec) {
    if (Test-WslKeepalive) {
        Write-Log "wsl ensure: $Distro keepalive already running; skip"
        return $true
    }
    try {
        Start-Process -FilePath "wsl.exe" -ArgumentList "-d $Distro -e sleep infinity" -WindowStyle Hidden | Out-Null
        Write-Log "wsl ensure: $Distro keepalive process started"
        return $true
    }
    catch {
        Write-Log "wsl ensure: $Distro launch failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-WslKeepalive {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'wsl.exe' -and $_.CommandLine -like '*sleep infinity*' }
    return @($procs).Count -gt 0
}

function Get-ListenerPids([int]$Port) {
    $pids = @()
    try {
        $lines = @(netstat -ano | Where-Object { $_ -match ":${Port}\s" -and $_ -match "LISTENING" })
        foreach ($line in $lines) {
            $parts = ($line.Trim() -split '\s+')
            if ($parts.Count -ge 5) {
                $procId = 0
                if ([int]::TryParse($parts[-1], [ref]$procId) -and $procId -gt 0) {
                    $pids += $procId
                }
            }
        }
    } catch {}
    return @($pids | Sort-Object -Unique)
}

function Stop-DshProcesses {
    $ids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($procId in @(Get-ListenerPids $webPort)) {
        if (-not $ids.Contains($procId)) { [void]$ids.Add($procId) }
    }
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe' -or $_.Name -eq 'node.exe' -or $_.Name -eq 'cmd.exe') -and
            ($_.CommandLine -like '*run-dsh-web.ps1*' -or $_.CommandLine -like '*apps/cli/src/bin.ts*')
        }
    foreach ($p in $procs) {
        if (-not $ids.Contains([int]$p.ProcessId)) { [void]$ids.Add([int]$p.ProcessId) }
    }
    foreach ($id in $ids) {
        taskkill /PID $id /T /F 2>&1 | Out-Null
    }
    Start-Sleep -Seconds 2
}

function Wait-WebReady([int]$TimeoutSec, [string]$Phase) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $started = Get-Date
    while (-not (Test-DshAlive)) {
        Write-Heartbeat
        if ((Get-Date) -ge $deadline) {
            Write-Log "${Phase}: no ready server within $TimeoutSec s; restarting"
            Stop-DshProcesses
            Start-DshWeb
            $deadline = (Get-Date).AddSeconds($TimeoutSec)
            $started = Get-Date
            continue
        }
        Start-Sleep -Seconds $bootProbeIntervalSec
    }
    $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    Write-Log "${Phase}: server ready after $elapsed s"
}

# If this process is not elevated, relaunch itself with administrator
# privileges (a UAC prompt will appear when launched manually) and exit.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Write-Log "not elevated; trying to relaunch with administrator privileges"
        Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$PSCommandPath -Verb RunAs -WindowStyle Hidden
        exit 0
    } catch {
        Write-Log "elevation not supported or refused; continuing in current user context"
    }
}

# Single-instance guard: hold a named mutex for the lifetime of this process.
$singleInstance = New-Object System.Threading.Mutex($false, 'Local\dsh-watchdog-single-instance')
if (-not $singleInstance.WaitOne(0)) {
    Write-Log "another watchdog instance is already running; exiting"
    exit 0
}

Write-Log "watchdog v3 started (boot=$bootTimeoutSec s, poll=$pollIntervalSec s, failLimit=$consecutiveFailLimit)"
Write-Heartbeat

if (Test-DshAlive) {
    Write-Log "initial state: server already alive"
}
else {
    Write-Log "initial start: no server listening"
    if (-not (Test-DshStarting)) {
        Start-DshWeb
    }
    else {
        Write-Log "initial start: dsh is already starting; waiting"
    }
    Wait-WebReady $bootTimeoutSec "initial boot"
}

$fails = 0
$lastWslEnsure = Get-Date
while ($true) {
    if (Test-Path $StopFlag) {
        Write-Log "manual stop flag detected; watchdog exiting"
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
        exit 0
    }
    Write-Heartbeat
    if (((Get-Date) - $lastWslEnsure).TotalSeconds -ge $wslEnsureIntervalSec) {
        if (-not (Test-WslGateway)) {
            Write-Log "wsl ensure: gateway missing; starting $wslDistro"
            Start-DshWsl $wslDistro $wslStartTimeoutSec
            Start-Sleep -Seconds 2
            if (-not (Test-WslGateway)) {
                Write-Log "wsl ensure: gateway still missing after start"
            }
        }
        $lastWslEnsure = Get-Date
    }
    Start-Sleep -Seconds $pollIntervalSec
    if (Test-DshAlive) {
        if ($fails -gt 0) {
            Write-Log "server recovered (fails=$fails)"
        }
        $fails = 0
        continue
    }
    $fails++
    Write-Log "probe failed ($fails/$consecutiveFailLimit)"
    if ($fails -ge $consecutiveFailLimit) {
        Write-Log "restarting after $fails consecutive failed probes"
        Stop-DshProcesses
        Start-DshWeb
        $fails = 0
        Wait-WebReady $bootTimeoutSec "restart boot"
    }
}
