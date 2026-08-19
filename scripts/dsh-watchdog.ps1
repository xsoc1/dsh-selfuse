$ErrorActionPreference = "Continue"
$log = "F:\tools\deepseek-harness\dsh-watchdog.log"
$runner = "F:\tools\deepseek-harness\run-dsh-web.ps1"
$heartbeat = "F:\tools\deepseek-harness\dsh-watchdog.heartbeat"
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

function Write-Heartbeat {
    try {
        [System.IO.File]::WriteAllText($heartbeat, "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    } catch {}
}

function Test-DshAlive {
    try {
        $r = Invoke-WebRequest -Uri $probe -UseBasicParsing -TimeoutSec $probeTimeoutSec
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
    Write-Log "not elevated; relaunching with administrator privileges"
    Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$PSCommandPath -Verb RunAs -WindowStyle Hidden
    exit 0
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
while ($true) {
    Write-Heartbeat
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
