$ErrorActionPreference = 'Stop'
$packageRoot = Split-Path -Parent $PSScriptRoot
$harnessRoot = (Resolve-Path (Join-Path $packageRoot '..\..\..')).Path
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('dsh-gui-check-' + [Guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$process = $null

function Wait-ForFile([string]$Path, [int]$Seconds) {
    $until = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $until) {
        if (Test-Path -LiteralPath $Path) { return $true }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

try {
    $statusFile = Join-Path $tempRoot 'status.json'
    $triggerFile = Join-Path $tempRoot 'refresh.trigger'
    $cmdFile = Join-Path $tempRoot 'cmd.json'
    $resultPrefix = Join-Path $tempRoot 'result-'
    $activityFile = Join-Path $tempRoot 'activity.log'
    $pidFile = Join-Path $tempRoot 'poller.pid'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $packageRoot 'dsh-gui-poller.ps1') + '"' +
        ' -StatusFile "' + $statusFile + '" -TriggerFile "' + $triggerFile + '" -CmdFile "' + $cmdFile + '"' +
        ' -ResultPrefix "' + $resultPrefix + '" -ActivityFile "' + $activityFile + '"' +
        ' -WebUrl "http://127.0.0.1:3080" -WebPort 3080' +
        ' -DshHome "\\wsl.localhost\Ubuntu\home\huangzy\.dsh" -DshProfile "\\wsl.localhost\Ubuntu\home\huangzy\.dsh\profiles\web"' +
        ' -WatchdogFile "' + (Join-Path $harnessRoot 'dsh-watchdog.ps1') + '"' +
        ' -WebLog "' + (Join-Path $harnessRoot 'dsh-web.log') + '"' +
        ' -WatchdogLog "' + (Join-Path $harnessRoot 'dsh-watchdog.log') + '"' +
        ' -HarnessRoot "' + $harnessRoot + '" -PollerPidFile "' + $pidFile + '" -Interval 1'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not (Wait-ForFile $statusFile 12)) { throw 'poller did not write a status snapshot' }

    foreach ($action in @('remote-health', 'update-preflight')) {
        $id = [Guid]::NewGuid().ToString('N')
        $resultFile = $resultPrefix + $id + '.json'
        [System.IO.File]::WriteAllText($cmdFile, ('{"id":"' + $id + '","action":"' + $action + '"}'), [System.Text.Encoding]::UTF8)
        if (-not (Wait-ForFile $resultFile 20)) { throw "$action did not return" }
        $result = Get-Content -LiteralPath $resultFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $joined = @($result.lines) -join "`n"
        if ($action -eq 'remote-health') {
            foreach ($text in @('本机 Web:', 'Tailscale:', '最近 Web', 'iPad')) {
                if (-not $joined.Contains($text)) { throw "remote-health missing $text" }
            }
        } else {
            foreach ($text in @('活跃 WSL 工作树:', '当前 HEAD:', '远端 HEAD:', '预检只读:')) {
                if (-not $joined.Contains($text)) { throw "update-preflight missing $text" }
            }
        }
    }
    Write-Host 'GREEN isolated diagnostic actions passed'
} finally {
    if ($process -and -not $process.HasExited) {
        $process.Kill()
        $process.WaitForExit(3000) | Out-Null
    }
    if ($process) { $process.Dispose() }
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}
