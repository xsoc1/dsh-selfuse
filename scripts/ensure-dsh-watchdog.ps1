$ErrorActionPreference = "Continue"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$HarnessRoot = Join-Path $RepoRoot "vendor\deepseek-harness"
if (-not (Test-Path (Join-Path $HarnessRoot "package.json"))) {
    if ($env:DSH_ROOT -and (Test-Path (Join-Path $env:DSH_ROOT "package.json"))) {
        $HarnessRoot = $env:DSH_ROOT
    } else {
        $HarnessRoot = "F:\tools\deepseek-harness"
    }
}
$log = "$HarnessRoot\dsh-watchdog.log"
$runner = "$HarnessRoot\dsh-watchdog.ps1"
$heartbeat = "$HarnessRoot\dsh-watchdog.heartbeat"
$staleSec = 90

function Get-WatchdogProcesses {
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
    return ($newest.CreationDate -gt (Get-Date).AddSeconds(-120))
}

if (Test-WatchdogHealthy) {
    exit 0
}

Add-Content -LiteralPath $log -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  ensure: watchdog missing or heartbeat stale, relaunching" -Encoding UTF8
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-WindowStyle","Hidden","-File",$runner -WindowStyle Hidden
