function Find-DshServeRoute([string]$StatusJson, [int]$WebPort) {
    try {
        $document = $StatusJson | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return @{ state = 'invalid'; url = ''; target = ''; public = $false }
    }
    if (-not $document) { return @{ state = 'invalid'; url = ''; target = ''; public = $false } }
    $scopes = @($document)
    if ($document.Services) {
        $scopes += @($document.Services.PSObject.Properties | ForEach-Object { $_.Value })
    }
    if ($document.Foreground) {
        $scopes += @($document.Foreground.PSObject.Properties | ForEach-Object { $_.Value })
    }
    $wrongTarget = ''
    $httpOnly = $false
    foreach ($scope in $scopes) {
        if (-not $scope.Web) { continue }
        foreach ($site in $scope.Web.PSObject.Properties) {
            $siteUri = $null
            if (-not [Uri]::TryCreate(('https://' + $site.Name), [UriKind]::Absolute, [ref]$siteUri)) { continue }
            $handler = $site.Value.Handlers.PSObject.Properties['/']
            if (-not $handler -or -not $handler.Value.Proxy) { continue }
            $targetUri = $null
            if (-not [Uri]::TryCreate([string]$handler.Value.Proxy, [UriKind]::Absolute, [ref]$targetUri)) { continue }
            $target = $targetUri.Host + ':' + $targetUri.Port
            $tcpPort = if ($scope.TCP) { $scope.TCP.PSObject.Properties[[string]$siteUri.Port] } else { $null }
            $isHttps = ($tcpPort -and $tcpPort.Value.HTTPS -eq $true)
            $matchesDsh = ($targetUri.Scheme -eq 'http' -and $targetUri.IsLoopback -and $targetUri.Port -eq $WebPort -and $targetUri.AbsolutePath -eq '/')
            if ($matchesDsh -and $isHttps) {
                $topFunnel = if ($document.AllowFunnel) { $document.AllowFunnel.PSObject.Properties[$site.Name] } else { $null }
                $scopeFunnel = if ($scope.AllowFunnel) { $scope.AllowFunnel.PSObject.Properties[$site.Name] } else { $null }
                $isPublic = (($topFunnel -and $topFunnel.Value -eq $true) -or ($scopeFunnel -and $scopeFunnel.Value -eq $true))
                return @{ state = 'ready'; url = $siteUri.GetLeftPart([UriPartial]::Authority); target = $target; public = $isPublic }
            }
            if ($matchesDsh) { $httpOnly = $true }
            elseif (-not $wrongTarget) { $wrongTarget = $target }
        }
    }
    if ($httpOnly) { return @{ state = 'http-only'; url = ''; target = '127.0.0.1:' + $WebPort; public = $false } }
    if ($wrongTarget) { return @{ state = 'wrong-target'; url = ''; target = $wrongTarget; public = $false } }
    return @{ state = 'missing'; url = ''; target = ''; public = $false }
}

function Get-DirectHttpStatus([string]$Url) {
    $request = $null
    try {
        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.Method = 'GET'
        $request.Proxy = $null
        $request.Timeout = 3000
        $request.ReadWriteTimeout = 3000
        $request.KeepAlive = $false
        $request.AllowAutoRedirect = $false
        $response = $request.GetResponse()
        try { return 'HTTP ' + [int]$response.StatusCode }
        finally { $response.Close() }
    } catch [System.Net.WebException] {
        if ($_.Exception.Response) {
            $response = $_.Exception.Response
            try { return 'HTTP ' + [int]$response.StatusCode }
            finally { $response.Close() }
        }
        return '连接失败'
    } catch {
        return '检查失败'
    } finally {
        if ($request) { $request.Abort() }
    }
}

function Get-RemoteHealthReport([int]$WebPort, [string]$WebLog) {
    $lines = @('== 远程健康检查（只读） ==')
    $localHttp = if (Get-PortOpen $WebPort) { Get-HttpStatus } else { '端口未监听' }
    $lines += '本机 Web: ' + $localHttp

    $ts = Resolve-TailscaleExe
    $service = Get-Service -Name Tailscale -ErrorAction SilentlyContinue
    if (-not $ts) {
        $lines += 'Tailscale: 未安装；Serve 与 Tailnet HTTPS 未检查'
    } elseif (-not $service -or $service.Status -ne 'Running') {
        $lines += 'Tailscale: 服务未运行；Serve 与 Tailnet HTTPS 未检查'
    } else {
        $statusResult = Invoke-TailscaleCommand $ts @('status', '--json')
        $status = $null
        if ($statusResult.ok) {
            try { $status = $statusResult.output | ConvertFrom-Json -ErrorAction Stop } catch { }
        }
        $ip = if ($status) { @($status.Self.TailscaleIPs) | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' } | Select-Object -First 1 } else { $null }
        if (-not $status) {
            $lines += 'Tailscale: 状态命令失败；Serve 与 Tailnet HTTPS 未检查'
        } elseif ($status.BackendState -ne 'Running' -or -not $ip) {
            $lines += 'Tailscale: ' + [string]$status.BackendState + '（无可用 Tailnet IPv4）；Serve 与 Tailnet HTTPS 未检查'
        } else {
            $lines += 'Tailscale: Running，Tailnet IP ' + $ip
            $serveResult = Invoke-TailscaleCommand $ts @('serve', 'status', '--json')
            if (-not $serveResult.ok) {
                $lines += 'Serve: 状态命令失败；Tailnet HTTPS 未检查'
            } else {
                $route = Find-DshServeRoute $serveResult.output $WebPort
                switch ($route.state) {
                    'ready' {
                        $lines += 'Serve: HTTPS 根路径转发至本机端口 ' + $WebPort
                        $lines += 'Tailnet 地址: ' + $route.url
                        if ($route.public) { $lines += '警告: 此地址启用了 Funnel 公网访问' }
                        else { $lines += 'Funnel: 此地址未启用公网访问' }
                        $lines += '本机经 Tailnet HTTPS: ' + (Get-DirectHttpStatus ($route.url + '/'))
                    }
                    'http-only' { $lines += 'Serve: 目标端口正确，但没有 HTTPS 监听；Tailnet HTTPS 未检查' }
                    'wrong-target' { $lines += 'Serve: HTTPS 根路径未转发至 DSH（当前目标 ' + $route.target + '）；Tailnet HTTPS 未检查' }
                    'invalid' { $lines += 'Serve: JSON 无法解析；Tailnet HTTPS 未检查' }
                    default { $lines += 'Serve: 未找到转发至 DSH 的根路径；Tailnet HTTPS 未检查' }
                }
            }
        }
    }

    if (Test-Path -LiteralPath $WebLog) {
        $recent = @(Get-Content -LiteralPath $WebLog -Tail 200 -Encoding UTF8 -ErrorAction SilentlyContinue)
        $matches = @($recent | Where-Object { $_ -match '(?i)error|failed|timeout|reconnect|失败|超时|重连' })
        $lines += '最近 Web 日志 200 行错误/重连关键词命中: ' + $matches.Count + '（不含日志正文）'
    } else {
        $lines += '最近 Web 错误: 日志不可用'
    }
    $lines += '边界: 本机探测不代表 iPad 浏览器会话正常'
    return $lines
}

function Get-UpdatePreflightReport {
    $scriptPath = '/home/huangzy/tools/deepseek-harness-current/packages/selfuse/control-gui/dsh-update-preflight.sh'
    $process = $null
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'wsl.exe'
        $psi.Arguments = '-d Ubuntu -e bash -lc "bash ' + $scriptPath + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process = [System.Diagnostics.Process]::Start($psi)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(11500)) {
            try { $process.Kill(); $process.WaitForExit(1000) } catch { }
            return @('== 更新预检（只读） ==', 'WSL 查询超时；未判断是否有更新')
        }
        $output = $outputTask.Result
        $null = $errorTask.Result
        $lines = @('== 更新预检（只读） ==')
        $lines += @($output -split "`r?`n" | Where-Object { $_.Trim() })
        if ($process.ExitCode -ne 0) { $lines += '预检失败（WSL 退出码 ' + $process.ExitCode + '）' }
        return $lines
    } catch {
        return @('== 更新预检（只读） ==', 'WSL 预检无法启动: ' + $_.Exception.Message)
    } finally {
        if ($process) { $process.Dispose() }
    }
}
