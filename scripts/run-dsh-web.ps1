$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location "F:\tools\deepseek-harness"
$stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$line = "==== dsh web start $stamp ===="
Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value $line -Encoding UTF8

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

$wslNic = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "vEthernet (WSL (Hyper-V firewall))" -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "172.*" } | Select-Object -First 1
$gateway = $null
if ($wslNic) { $gateway = $wslNic.IPAddress }

$trustedArgs = @("--host", "127.0.0.1")
if ($gateway) {
    if (Test-TcpPort $gateway 3080) {
        Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "wsl portproxy already listening on $gateway`:3080; skipping netsh" -Encoding UTF8
    }
    else {
        $proxyExists = netsh interface portproxy show v4tov4 2>&1 | Where-Object { $_ -match "^\s*$gateway\s+3080" }
        if ($proxyExists) {
            Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "wsl portproxy entry $gateway`:3080 already present; skipping netsh" -Encoding UTF8
        }
        else {
            netsh interface portproxy delete v4tov4 listenaddress=$gateway listenport=3080 2>&1 | Out-Null
            netsh interface portproxy add v4tov4 listenaddress=$gateway listenport=3080 connectaddress=127.0.0.1 connectport=3080 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            if (-not (Test-TcpPort $gateway 3080)) {
                Restart-Service iphlpsvc -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "wsl portproxy: iphlpsvc restarted to bind $gateway`:3080" -Encoding UTF8
            }
        }
    }
    $trustedArgs += @("--trusted-host", $gateway)
    Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "wsl portproxy $gateway`:3080 -> 127.0.0.1:3080" -Encoding UTF8
}
else {
    Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "wsl gateway not found; skipping portproxy/trusted-host" -Encoding UTF8
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
        Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "tailscale serve host: $tailscaleHost (trusted-host added)" -Encoding UTF8
        $serveStatusText = & $tailscaleExe serve status 2>&1 | Out-String
        if ($serveStatusText -match 'No serve config') {
            Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "tailscale serve not enabled; open https://login.tailscale.com/f/serve?node=ny59qLPW6Y11CNTRL to enable" -Encoding UTF8
        }
        else {
            & $tailscaleExe serve --bg 3080 2>&1 | Out-Null
            Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "tailscale serve ensured: https://$tailscaleHost -> http://127.0.0.1:3080" -Encoding UTF8
        }
    }
    else {
        Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "tailscale not logged in; skipping tailscale serve/trusted-host" -Encoding UTF8
    }
}
else {
    Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "tailscale not found; skipping tailscale serve/trusted-host" -Encoding UTF8
}

$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { $node = "node.exe" }
& $node --import tsx/esm apps/cli/src/bin.ts web @trustedArgs 2>&1 | ForEach-Object { Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value $_ -Encoding UTF8 }
Add-Content -LiteralPath "F:\tools\deepseek-harness\dsh-web.log" -Value "==== dsh web exit ====" -Encoding UTF8
