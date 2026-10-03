$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'remove-tailscale-forced-derp.ps1')
$Utf8 = New-Object Text.UTF8Encoding($false, $true)
$UnicodeText = [string][char]0x4e2d + [string][char]0x6587
$Cases = @(
    @{ before = "KEEP=$UnicodeText`r`nTS_DEBUG_ALWAYS_USE_DERP=1`r`nOTHER=2`r`n"; after = "KEEP=$UnicodeText`r`nOTHER=2`r`n" },
    @{ before = "TS_DEBUG_ALWAYS_USE_DERP=1`nKEEP=1`n"; after = "KEEP=1`n" },
    @{ before = "KEEP=1`nTS_DEBUG_ALWAYS_USE_DERP=1"; after = "KEEP=1`n" },
    @{ before = " TS_DEBUG_ALWAYS_USE_DERP = 1 `n# TS_DEBUG_ALWAYS_USE_DERP=1`n"; after = "# TS_DEBUG_ALWAYS_USE_DERP=1`n" },
    @{ before = ([string][char]0xFEFF + "TS_DEBUG_ALWAYS_USE_DERP=1`r`nKEEP=1`r`n"); after = ([string][char]0xFEFF + "KEEP=1`r`n") }
)
foreach ($Case in $Cases) {
    $Actual = Remove-ForcedDerpBytes ($Utf8.GetBytes($Case.before))
    if ([Convert]::ToBase64String($Actual) -cne [Convert]::ToBase64String($Utf8.GetBytes($Case.after))) { throw 'Unrelated bytes changed.' }
}
foreach ($Bad in @("KEEP=1`n", "TS_DEBUG_ALWAYS_USE_DERP=0`n", "TS_DEBUG_ALWAYS_USE_DERP=1`nTS_DEBUG_ALWAYS_USE_DERP=1`n", "TS_DEBUG_ALWAYS_USE_DERP=1 # ambiguous`n", ([string][char]0 + 'TS_DEBUG_ALWAYS_USE_DERP=1'))) {
    $Rejected = $false
    try { Remove-ForcedDerpBytes ($Utf8.GetBytes($Bad)) | Out-Null } catch { $Rejected = $true }
    if (-not $Rejected) { throw 'Unsafe or unsupported input was accepted.' }
}
Write-Output '10 byte-preservation/rejection cases passed; no service or real environment changed.'
