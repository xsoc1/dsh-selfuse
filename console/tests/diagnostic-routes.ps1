$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'dsh-gui-probes.ps1')

$good = '{"TCP":{"443":{"HTTPS":true}},"Web":{"node.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3080"}}}}}'
$nested = '{"Services":{"svc:dsh":{"TCP":{"443":{"HTTPS":true}},"Web":{"dsh.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://localhost:3080/"}}}}}}}'
$wrong = '{"TCP":{"443":{"HTTPS":true}},"Web":{"node.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}}}'
$httpOnly = '{"TCP":{"443":{"HTTP":true}},"Web":{"node.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3080"}}}}}'
$wrongPath = '{"TCP":{"443":{"HTTPS":true}},"Web":{"node.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3080/other"}}}}}'
$funnel = '{"TCP":{"443":{"HTTPS":true}},"Web":{"node.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3080"}}}},"AllowFunnel":{"node.tailnet.ts.net:443":true}}'
$foreground = '{"Foreground":{"session":{"TCP":{"443":{"HTTPS":true}},"Web":{"fg.tailnet.ts.net:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:3080"}}}}}}}'

$cases = @(
    @{ name = 'root route'; json = $good; state = 'ready'; url = 'https://node.tailnet.ts.net'; public = $false }
    @{ name = 'service route'; json = $nested; state = 'ready'; url = 'https://dsh.tailnet.ts.net'; public = $false }
    @{ name = 'funnel route'; json = $funnel; state = 'ready'; url = 'https://node.tailnet.ts.net'; public = $true }
    @{ name = 'foreground route'; json = $foreground; state = 'ready'; url = 'https://fg.tailnet.ts.net'; public = $false }
    @{ name = 'wrong target'; json = $wrong; state = 'wrong-target'; url = '' }
    @{ name = 'http only'; json = $httpOnly; state = 'http-only'; url = '' }
    @{ name = 'wrong path'; json = $wrongPath; state = 'wrong-target'; url = '' }
    @{ name = 'no config'; json = '{}'; state = 'missing'; url = '' }
    @{ name = 'invalid json'; json = '{'; state = 'invalid'; url = '' }
)
$failures = @()
foreach ($case in $cases) {
    $actual = Find-DshServeRoute $case.json 3080
    if ($actual.state -ne $case.state -or $actual.url -ne $case.url -or ($case.ContainsKey('public') -and $actual.public -ne $case.public)) {
        $failures += "$($case.name): expected $($case.state) $($case.url), got $($actual.state) $($actual.url)"
    }
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host "RED $_" }
    exit 1
}
Write-Host 'GREEN Serve route diagnostic cases passed'
