$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$RepoRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $PSScriptRoot 'package.json')) {
    $HarnessRoot = $PSScriptRoot
} else {
    $HarnessRoot = Join-Path $RepoRoot 'vendor\deepseek-harness'
    if (-not (Test-Path (Join-Path $HarnessRoot 'package.json'))) {
        if ($env:DSH_ROOT -and (Test-Path (Join-Path $env:DSH_ROOT 'package.json'))) {
            $HarnessRoot = $env:DSH_ROOT
        } elseif (Test-Path '\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness\package.json') {
            $HarnessRoot = '\\wsl.localhost\Ubuntu\home\huangzy\tools\deepseek-harness'
        } elseif (Test-Path 'F:\tools\deepseek-harness\package.json') {
            $HarnessRoot = 'F:\tools\deepseek-harness'
        }
    }
}
Set-Location "$HarnessRoot"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$line = "==== dsh web start $stamp ===="
Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value $line -Encoding UTF8

$clientBundles = @(
    'packages/client/ui-reference/lib/client.js',
    'packages/client/ui-renderer/lib/client.js',
    'packages/client/ui-attachment/lib/client.js',
    'packages/client/ui-brand-official/lib/client.js',
    'apps/web/dist/index.html'
)
$missingBundles = @($clientBundles | Where-Object { -not (Test-Path (Join-Path $HarnessRoot $_)) })
if ($missingBundles.Count -gt 0) {
    Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "preflight: missing client bundles ($($missingBundles -join ', ')); rebuilding" -Encoding UTF8
    $pnpm = Join-Path $HarnessRoot 'node_modules\.bin\pnpm.cmd'
    & $pnpm run build:lib:client
    if ($LASTEXITCODE -ne 0) { throw "preflight build:lib:client failed (exit $LASTEXITCODE)" }
    & $pnpm run build:web
    if ($LASTEXITCODE -ne 0) { throw "preflight build:web failed (exit $LASTEXITCODE)" }
}

function Test-TcpPort([string]$HostName, [int]$Port) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne(500)
        if ($ok) { $client.EndConnect($iar) }
        $client.Close()
        return $ok
    } catch {
        return $false
    }
}

$wslDistro = "Ubuntu"
$wslStartTimeoutSec = 20
$wslGatewayTimeoutSec = 30

function Start-DshWsl([string]$Distro, [int]$TimeoutSec) {
    $log = "$HarnessRoot\dsh-web.log"
    if (Test-WslKeepalive) {
        Add-Content -LiteralPath $log -Value "wsl auto-start: $Distro keepalive already running; skip" -Encoding UTF8
        return $true
    }
    try {
        Start-Process -FilePath "wsl.exe" -ArgumentList "-d $Distro -e sleep infinity" -WindowStyle Hidden | Out-Null
        Add-Content -LiteralPath $log -Value "wsl auto-start: $Distro keepalive process started" -Encoding UTF8
        return $true
    }
    catch {
        Add-Content -LiteralPath $log -Value "wsl auto-start: $Distro launch failed: $($_.Exception.Message)" -Encoding UTF8
        return $false
    }
}

function Test-WslKeepalive {
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'wsl.exe' -and $_.CommandLine -like '*sleep infinity*' }
    return @($procs).Count -gt 0
}

function Get-WslGateway([int]$TimeoutSec) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $nic = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "vEthernet (WSL (Hyper-V firewall))" -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "172.*" } | Select-Object -First 1
        if ($nic) { return $nic.IPAddress }
        Start-Sleep -Seconds 2
    }
    return $null
}

Start-DshWsl $wslDistro $wslStartTimeoutSec
$gateway = Get-WslGateway $wslGatewayTimeoutSec
if (-not $gateway) {
    Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "wsl auto-start: gateway not found after $wslGatewayTimeoutSec s" -Encoding UTF8
}

$trustedArgs = @("--host", "127.0.0.1")
if ($gateway) {
    if (Test-TcpPort $gateway 3080) {
        Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "wsl portproxy already listening on $gateway`:3080; skipping netsh" -Encoding UTF8
    }
    else {
        $proxyExists = netsh interface portproxy show v4tov4 2>&1 | Where-Object { $_ -match "^\s*$gateway\s+3080" }
        if ($proxyExists) {
            Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "wsl portproxy entry $gateway`:3080 already present; skipping netsh" -Encoding UTF8
        }
        else {
            netsh interface portproxy delete v4tov4 listenaddress=$gateway listenport=3080 2>&1 | Out-Null
            netsh interface portproxy add v4tov4 listenaddress=$gateway listenport=3080 connectaddress=127.0.0.1 connectport=3080 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            if (-not (Test-TcpPort $gateway 3080)) {
                Restart-Service iphlpsvc -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "wsl portproxy: iphlpsvc restarted to bind $gateway`:3080" -Encoding UTF8
            }
        }
    }
    $trustedArgs += @("--trusted-host", $gateway)
    Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "wsl portproxy $gateway`:3080 -> 127.0.0.1:3080" -Encoding UTF8
}
else {
    Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "wsl gateway not found; skipping portproxy/trusted-host" -Encoding UTF8
}

# Tailscale 私有远程：通过 Tailscale Serve 暴露 https://<machine>.<tailnet>.ts.net -> 127.0.0.1:3080
$tailscaleExe = "F:\Tailscale\tailscale.exe"
$tailscaleHost = $null
if (Test-Path $tailscaleExe) {
    try {
        $tsSelf = & $tailscaleExe status --json 2>$null | ConvertFrom-Json | Select-Object -ExpandProperty Self
        if ($tsSelf) { $tailscaleHost = ($tsSelf.DNSName -replace '\.$', '') }
    } catch {
        $tailscaleHost = $null
    }
    if ($tailscaleHost) {
        $trustedArgs += @("--trusted-host", $tailscaleHost)
        Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "tailscale serve host: $tailscaleHost (trusted-host added)" -Encoding UTF8
        $serveStatusText = & $tailscaleExe serve status 2>&1 | Out-String
        if ($serveStatusText -match 'No serve config') {
            Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "tailscale serve not enabled; open https://login.tailscale.com/f/serve?node=ny59qLPW6Y11CNTRL to enable" -Encoding UTF8
        }
        else {
            & $tailscaleExe serve --bg 3080 2>&1 | Out-Null
            Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "tailscale serve ensured: https://$tailscaleHost -> http://127.0.0.1:3080" -Encoding UTF8
        }
    }
    else {
        Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "tailscale not logged in; skipping tailscale serve/trusted-host" -Encoding UTF8
    }
}
else {
    Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "tailscale not found; skipping tailscale serve/trusted-host" -Encoding UTF8
}

# Run dsh inside WSL (Linux filesystem) with WSL native Node/pnpm.
$wslCommand = "cd '/home/huangzy/tools/deepseek-harness' && export PATH=/home/huangzy/.local/bin:`$PATH && export DSH_HOME='/home/huangzy/.dsh' && unset DSH_SESSION_ID DSH_SESSION_JSONL DSH_WEB_URL DSH_WSL_DISTRO && node --import tsx/esm apps/cli/src/bin.ts web $($trustedArgs -join ' ')"
$launchToken = $null
& wsl.exe -d Ubuntu -- bash -lc $wslCommand 2>&1 | ForEach-Object {
    Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value $_ -Encoding UTF8
    if ($_ -match 'http://127\.0\.0\.1:3080/\?token=([A-Za-z0-9_-]+)' -and $launchToken -eq $null) {
        $launchToken = $Matches[1]
        if ($tailscaleHost) {
            Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "dsh web remote: https://$tailscaleHost/?token=$launchToken" -Encoding UTF8
        }
    }
}
Add-Content -LiteralPath "$HarnessRoot\dsh-web.log" -Value "==== dsh web exit ====" -Encoding UTF8
