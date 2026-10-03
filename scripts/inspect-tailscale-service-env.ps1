# Read-only administrator probe. Never prints the service environment or credentials.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this read-only probe from an administrator PowerShell.'
}
$Root = 'F:\Apps\DeepSeekHarnessRemote'
if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw 'Protected deployment root missing.' }
$EnvPath = 'C:\ProgramData\Tailscale\tailscaled-env.txt'
$Record = [ordered]@{ time = [DateTime]::UtcNow.ToString('o'); fileExists = $false; forcedDerp = $false; activeFlagCount = 0; changed = $false }
if (Test-Path -LiteralPath $EnvPath -PathType Leaf) {
    if (-not ('DshTailEnvNativePath' -as [type])) { Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class DshTailEnvNativePath {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder path, uint size, uint flags);
}
'@
    }
    $Stream = [IO.File]::Open($EnvPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $Buffer = New-Object Text.StringBuilder(1024)
        $Size = [DshTailEnvNativePath]::GetFinalPathNameByHandle($Stream.SafeFileHandle, $Buffer, 1024, 0)
        if ($Size -eq 0 -or $Size -ge 1024) { throw 'Native service environment path could not be verified.' }
        if ($Buffer.ToString() -ine ('\\?\' + $EnvPath)) { throw 'Service environment is redirected; inspect in a native administrator shell.' }
        $Reader = New-Object IO.StreamReader($Stream, [Text.Encoding]::UTF8, $true)
        try { $Text = $Reader.ReadToEnd() } finally { $Reader.Dispose() }
    } finally { $Stream.Dispose() }
    $Record.fileExists = $true
    $Flags = [regex]::Matches($Text, '(?m)^\s*TS_DEBUG_ALWAYS_USE_DERP\s*=\s*([^\r\n]*)')
    $Record.activeFlagCount = $Flags.Count
    $Record.forcedDerp = @($Flags | Where-Object { $_.Groups[1].Value.Trim() -eq '1' }).Count -gt 0
}
$Json = $Record | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $Root 'tailscale-service-env-inspection.json'), $Json, (New-Object Text.UTF8Encoding($false)))
Write-Output $Json
