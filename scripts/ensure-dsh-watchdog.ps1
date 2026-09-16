$ErrorActionPreference = "Continue"
$log = "F:\tools\deepseek-harness\dsh-watchdog.log"
$runner = "F:\tools\deepseek-harness\dsh-watchdog.ps1"
$heartbeat = "F:\tools\deepseek-harness\dsh-watchdog.heartbeat"
$pidFile = "F:\tools\deepseek-harness\dsh-watchdog.pid"
$stopFlag = "F:\tools\deepseek-harness\dsh-manual-stop.flag"
$staleSec = 90

if (Test-Path $stopFlag) {
    # User manually stopped DSH, do not auto-relaunch
    exit 0
}

function Get-WatchdogProcesses {
    if (Test-Path $pidFile) {
        $rawPid = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($rawPid -match '^\d+$') {
            try {
                $proc = [System.Diagnostics.Process]::GetProcessById([int]$rawPid)
                if ($proc -and -not $proc.HasExited -and ($proc.ProcessName -like '*powershell*' -or $proc.ProcessName -like '*pwsh*')) {
                    return @($proc)
                }
            } catch {}
        }
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe') -and
            $_.CommandLine -like '*dsh-watchdog.ps1*' -and
            $_.CommandLine -notlike '*ensure-dsh-watchdog.ps1*' -and
            $_.CommandLine -notlike '*dsh-control*' -and
            $_.CommandLine -notlike '*dsh-gui-poller.ps1*'
        }
}

function Test-WatchdogHealthy {
    $procs = @(Get-WatchdogProcesses)
    if ($procs.Count -eq 0) { return $false }
    if (Test-Path $heartbeat) {
        $age = (Get-Date) - (Get-Item -LiteralPath $heartbeat).LastWriteTime
        return ($age.TotalSeconds -le $staleSec)
    }
    $newest = $procs | Sort-Object CreationDate -Descending | Select-Object -First 1
    if ($newest.CreationDate) {
        return ($newest.CreationDate -gt (Get-Date).AddSeconds(-120))
    }
    return $true
}

if (Test-WatchdogHealthy) {
    exit 0
}

Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  ensure: watchdog missing or heartbeat stale, relaunching" -Encoding UTF8
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$runner -WindowStyle Hidden
