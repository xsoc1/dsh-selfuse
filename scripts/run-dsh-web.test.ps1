$ErrorActionPreference = 'Stop'
$RunnerPath = Join-Path $PSScriptRoot 'run-dsh-web.ps1'
$parseErrors = @()
$ast = [System.Management.Automation.Language.Parser]::ParseFile($RunnerPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) { throw "Startup script has $($parseErrors.Count) parse errors" }

$functionAst = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ConfiguredTailnetHost'
}, $true)
if (-not $functionAst) { throw 'Get-ConfiguredTailnetHost is missing' }
. ([ScriptBlock]::Create($functionAst.Extent.Text))

$valid = "remote-web-ui:`n  publicBaseUrl: 'https://machine.example.ts.net'`n"
if ((Get-ConfiguredTailnetHost $valid) -ne 'machine.example.ts.net') { throw 'Valid Tailnet URL was not resolved' }
$invalid = @(
    "other-plugin:`n  publicBaseUrl: 'https://machine.example.ts.net'`n",
    "remote-web-ui:`n  publicBaseUrl: 'http://machine.example.ts.net'`n",
    "remote-web-ui:`n  publicBaseUrl: 'https://attacker.example'`n",
    "remote-web-ui:`n  publicBaseUrl: 'https://machine.example.ts.net.evil.example'`n",
    "remote-web-ui:`n  publicBaseUrl: 'https://machine.example.ts.net/path'`n",
    "remote-web-ui:`n  publicBaseUrl: 'https://machine.example.ts.net:444'`n",
    "remote-web-ui:`n  publicBaseUrl: 'https://user@machine.example.ts.net'`n",
    "remote-web-ui:`n  publicBaseUrl: 'https://machine.example.ts.net/?next=other'`n"
)
foreach ($settings in $invalid) {
    if (Get-ConfiguredTailnetHost $settings) { throw 'Invalid URL became a trusted host' }
}

$source = Get-Content -LiteralPath $RunnerPath -Raw -Encoding UTF8
if ($source -notmatch '\$configuredTailnetHost\s*=\s*Get-ConfiguredTailnetHost') { throw 'Startup does not read the configured Tailnet host' }
if ($source -notmatch '\$trustedArgs\s*\+=\s*@\("--trusted-host",\s*\$trustedTailnetHost\)') { throw 'Startup does not pass the trusted Tailnet host' }
Write-Output 'run-dsh-web trusted-host regression: PASS'
