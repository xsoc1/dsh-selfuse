param(
    [ValidateSet('Prepare', 'Stage', 'Firewall', 'Verify', 'RemoveFirewall', 'ArchiveConfig')]
    [string]$Action = 'Verify'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$TrialRoot = 'F:\Apps\RustDeskTrial'
$ExePath = Join-Path $TrialRoot 'app\RustDesk.exe'
$LibraryPath = Join-Path $TrialRoot 'app\librustdesk.dll'
$StatePath = Join-Path $TrialRoot 'trial-state.json'
$ConfigRoot = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'RustDesk'
$ConfigPath = Join-Path $ConfigRoot 'config\RustDesk2.toml'
$TailscalePath = 'C:\Program Files\Tailscale\tailscale.exe'
$RuleGroup = 'DSH RustDesk private trial 20261003'
$RulePrefix = 'DSH-RustDeskTrial-20261003-'
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$TemplatePath = Join-Path $PSScriptRoot '..\config\remote\rustdesk-trial.toml'
$StagePath = Join-Path $TrialRoot 'staged\RustDesk2.toml'

trap {
    if (Test-Path -LiteralPath $TrialRoot) {
        $Failure = [pscustomobject]@{ Action = $Action; Time = [DateTimeOffset]::Now.ToString('o'); Error = $_.Exception.Message }
        [IO.File]::WriteAllText((Join-Path $TrialRoot 'last-error.json'), ($Failure | ConvertTo-Json), $Utf8)
    }
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}

function Test-Admin {
    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = New-Object System.Security.Principal.WindowsPrincipal($Identity)
    return $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-RustDeskStopped {
    if (@(Get-Process -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0 -or
        @(Get-Service -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Exit RustDesk normally before initializing its native profile.'
    }
}

function Initialize-NativeApi {
    if (-not ('RustDeskTrialStorage' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class RustDeskTrialStorage {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, StringBuilder buffer, uint length, uint flags);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)]
    public static extern int GetCurrentPackageFullName(ref uint length, IntPtr name);
}
'@
    }
}

function Assert-UnpackagedContext {
    Initialize-NativeApi
    # Child processes can inherit redirected storage without reporting package identity.
    if (Test-Path -LiteralPath $ConfigPath) { Assert-NativeStorage $ConfigPath }
    $Length = [uint32]0
    $Result = [RustDeskTrialStorage]::GetCurrentPackageFullName([ref]$Length, [IntPtr]::Zero)
    if ($Result -eq 122) {
        throw 'Native RustDesk setup must run outside MSIX/Codex. Open Windows PowerShell from the Windows Start menu.'
    }
    if ($Result -ne 15700) { throw "Cannot determine Windows package identity (status $Result)." }
}

function Get-StoragePath([string]$Path) {
    Initialize-NativeApi
    $Stream = [IO.File]::OpenRead($Path)
    try {
        $Buffer = New-Object Text.StringBuilder(32768)
        $Length = [RustDeskTrialStorage]::GetFinalPathNameByHandle($Stream.SafeFileHandle, $Buffer, 32768, 0)
        if ($Length -eq 0 -or $Length -ge 32768) { throw 'Cannot resolve actual configuration storage.' }
        $Actual = $Buffer.ToString()
        if ($Actual.StartsWith('\\?\UNC\')) { return '\\' + $Actual.Substring(8) }
        if ($Actual.StartsWith('\\?\')) { return $Actual.Substring(4) }
        return $Actual
    } finally { $Stream.Dispose() }
}

function Assert-NativeStorage([string]$Path) {
    $Actual = Get-StoragePath $Path
    $Expected = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals($Actual, $Expected, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Configuration is redirected to application-private storage, not the native RustDesk profile. Run Firewall from normal Windows PowerShell.'
    }
}

function Assert-Binaries {
    $Expected = @{
        $ExePath = '7F6D1E09E5A9924F567962AA57A6B126B409BED4775D98074C727420438768DC'
        $LibraryPath = 'DA4889603C26C6C29FDAA4BB3AEC857F9E714E9E795A2C031184BFF78FE7C597'
    }
    foreach ($Path in $Expected.Keys) {
        if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Expected[$Path]) {
            throw 'Pinned RustDesk 1.5.0 binary hash mismatch.'
        }
        if ((Get-AuthenticodeSignature -LiteralPath $Path).Status -ne 'Valid') {
            throw 'RustDesk signature validation failed.'
        }
    }
}

function Get-TailContext {
    if ((Get-AuthenticodeSignature -LiteralPath $TailscalePath).Status -ne 'Valid') {
        throw 'Tailscale executable signature validation failed.'
    }
    $Json = & $TailscalePath status --json
    if ($LASTEXITCODE -ne 0) { throw 'Tailscale status failed.' }
    $Status = $Json | ConvertFrom-Json
    if ($Status.BackendState -ne 'Running' -or -not $Status.Self.Online) {
        throw 'Tailscale must be online.'
    }
    $LocalIp = @($Status.Self.TailscaleIPs | Where-Object { $_ -notmatch ':' })
    $Mobiles = @($Status.Peer.PSObject.Properties.Value | Where-Object {
        $_.UserID -eq $Status.Self.UserID -and $_.OS -in @('iOS', 'android')
    })
    if ($LocalIp.Count -ne 1 -or $Mobiles.Count -lt 1 -or $Mobiles.Count -gt 4) {
        throw 'Expected one Windows IPv4 address and one to four same-owner mobile peers.'
    }
    $RemoteIps = @($Mobiles | ForEach-Object { $_.TailscaleIPs } |
        Where-Object { $_ -notmatch ':' } | Sort-Object -Unique)
    if ($RemoteIps.Count -ne $Mobiles.Count) { throw 'Each mobile must have one IPv4 address.' }
    foreach ($Ip in @($LocalIp[0]) + $RemoteIps) {
        $Bytes = [Net.IPAddress]::Parse($Ip).GetAddressBytes()
        if ($Bytes.Count -ne 4 -or $Bytes[0] -ne 100 -or $Bytes[1] -lt 64 -or $Bytes[1] -gt 127) {
            throw 'Only individual Tailscale IPv4 addresses are accepted.'
        }
    }
    [pscustomobject]@{ LocalIp = $LocalIp[0]; RemoteIps = $RemoteIps; Mobiles = $Mobiles }
}

function Get-DesktopHashes {
    $Profile = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh\profiles\desktop'
    @(Get-ChildItem -LiteralPath $Profile -File | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ Name = $_.Name; Sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash }
    })
}

function ConvertTo-IpNumber([string]$Ip) {
    $Bytes = [Net.IPAddress]::Parse($Ip).GetAddressBytes()
    if ($Bytes.Count -ne 4) { throw 'Only IPv4 is supported by this trial.' }
    return [uint64]$Bytes[0] * 16777216 + [uint64]$Bytes[1] * 65536 + [uint64]$Bytes[2] * 256 + $Bytes[3]
}

function ConvertFrom-IpNumber([uint64]$Number) {
    return '{0}.{1}.{2}.{3}' -f (($Number -shr 24) -band 255), (($Number -shr 16) -band 255), (($Number -shr 8) -band 255), ($Number -band 255)
}

function Get-IpComplement([string[]]$Allowed) {
    $Cursor = [uint64]0
    $Numbers = @($Allowed | ForEach-Object { ConvertTo-IpNumber $_ } | Sort-Object -Unique)
    foreach ($Number in $Numbers) {
        if ($Cursor -lt $Number) {
            '{0}-{1}' -f (ConvertFrom-IpNumber $Cursor), (ConvertFrom-IpNumber ($Number - 1))
        }
        $Cursor = [uint64]$Number + 1
    }
    if ($Cursor -le 4294967295) {
        '{0}-255.255.255.255' -f (ConvertFrom-IpNumber $Cursor)
    }
    # NetSecurity rejects /0 here. These disjoint /1 prefixes cover all IPv6.
    '::/1'
    '8000::/1'
}

function Get-RuleSpecs($State) {
    @(
        @{ Suffix = 'AllowDirect'; Direction = 'Inbound'; Action = 'Allow'; Protocol = 'TCP';
            LocalPort = '21118'; LocalAddress = @($State.LocalIp); RemoteAddress = @($State.RemoteIps); InterfaceAlias = 'Tailscale' },
        @{ Suffix = 'BlockOtherSources'; Direction = 'Inbound'; Action = 'Block'; Protocol = 'Any';
            LocalPort = 'Any'; LocalAddress = @('Any'); RemoteAddress = @(Get-IpComplement $State.RemoteIps); InterfaceAlias = 'Any' },
        @{ Suffix = 'BlockOtherDestinations'; Direction = 'Inbound'; Action = 'Block'; Protocol = 'Any';
            LocalPort = 'Any'; LocalAddress = @(Get-IpComplement @($State.LocalIp)); RemoteAddress = @('Any'); InterfaceAlias = 'Any' },
        @{ Suffix = 'BlockPublicOutbound'; Direction = 'Outbound'; Action = 'Block'; Protocol = 'Any';
            LocalPort = 'Any'; LocalAddress = @('Any'); RemoteAddress = @(Get-IpComplement (@($State.LocalIp, '127.0.0.1') + @($State.RemoteIps))); InterfaceAlias = 'Any' }
    )
}

function Test-SameSet($Left, $Right) {
    return (@(Compare-Object @($Left | Sort-Object -Unique) @($Right | Sort-Object -Unique)).Count -eq 0)
}

function Test-TrialRule($Rule, $Spec, [switch]$AllowDisabled) {
    if (@($Rule).Count -ne 1 -or -not $Rule) { return $false }
    $App = $Rule | Get-NetFirewallApplicationFilter
    $Port = $Rule | Get-NetFirewallPortFilter
    $Address = $Rule | Get-NetFirewallAddressFilter
    $Interface = $Rule | Get-NetFirewallInterfaceFilter
    $Service = $Rule | Get-NetFirewallServiceFilter
    # Native executable rules expose an unset Package as null, not "Any".
    $PackageUnrestricted = [string]::IsNullOrEmpty([string]$App.Package) -or $App.Package -eq 'Any'
    if ($Rule.Group -ne $RuleGroup -or $Rule.Profile.ToString() -ne 'Any' -or
        $Rule.Enabled.ToString() -notin @('True', 'False') -or
        (-not $AllowDisabled -and $Rule.Enabled.ToString() -ne 'True') -or
        $Rule.Direction.ToString() -ne $Spec.Direction -or $Rule.Action.ToString() -ne $Spec.Action -or
        $App.Program -ne $ExePath -or -not $PackageUnrestricted -or $Service.Service -ne 'Any' -or
        $Port.Protocol.ToString() -ne $Spec.Protocol -or -not (Test-SameSet $Port.LocalPort @($Spec.LocalPort)) -or
        -not (Test-SameSet $Port.RemotePort @('Any')) -or
        -not (Test-SameSet $Address.LocalAddress $Spec.LocalAddress) -or
        -not (Test-SameSet $Address.RemoteAddress $Spec.RemoteAddress) -or
        -not (Test-SameSet $Interface.InterfaceAlias @($Spec.InterfaceAlias))) { return $false }
    return $true
}

function Test-TrialRules($State) {
    foreach ($Spec in @(Get-RuleSpecs $State)) {
        $Rule = Get-NetFirewallRule -PolicyStore ActiveStore -Name ($RulePrefix + $Spec.Suffix) -ErrorAction SilentlyContinue
        if (-not (Test-TrialRule $Rule $Spec)) { return $false }
    }
    return $true
}

function Set-TrialFirewall($State) {
    Assert-RustDeskStopped
    $Specs = @(Get-RuleSpecs $State)
    $Existing = @(Get-NetFirewallRule -PolicyStore PersistentStore -Name ($RulePrefix + '*') -ErrorAction SilentlyContinue)
    # Validate every existing rule before changing any. Never overwrite a collision.
    foreach ($Rule in $Existing) {
        $Matching = @($Specs | Where-Object { ($RulePrefix + $_.Suffix) -eq $Rule.Name })
        if ($Matching.Count -ne 1 -or -not (Test-TrialRule $Rule $Matching[0] -AllowDisabled)) {
            throw 'Conflicting trial rule; no existing rules were changed.'
        }
    }
    $State.FirewallApplied = $false
    [IO.File]::WriteAllText($StatePath, ($State | ConvertTo-Json -Depth 5), $Utf8)
    $AllowName = $RulePrefix + 'AllowDirect'
    $CurrentStep = 'DisableDirectDuringRepair'
    try {
        $Allow = Get-NetFirewallRule -PolicyStore PersistentStore -Name $AllowName -ErrorAction SilentlyContinue
        if ($Allow) { Disable-NetFirewallRule -PolicyStore PersistentStore -Name $AllowName -ErrorAction Stop | Out-Null }
        # Complete all blockers before restoring/creating the narrow Allow.
        $Ordered = @($Specs | Where-Object Action -eq 'Block') + @($Specs | Where-Object Action -eq 'Allow')
        foreach ($Spec in $Ordered) {
            $CurrentStep = $Spec.Suffix
            $Name = $RulePrefix + $Spec.Suffix
            $Rule = Get-NetFirewallRule -PolicyStore PersistentStore -Name $Name -ErrorAction SilentlyContinue
            if ($Rule) {
                if ($Rule.Enabled.ToString() -ne 'True') {
                    Enable-NetFirewallRule -PolicyStore PersistentStore -Name $Name -ErrorAction Stop | Out-Null
                }
            } else {
                $Params = @{} + $Spec
                $Params.Remove('Suffix')
                New-NetFirewallRule @Params -PolicyStore PersistentStore -Name $Name -DisplayName $Name `
                    -Group $RuleGroup -Program $ExePath -Profile Any -Enabled True -ErrorAction Stop | Out-Null
            }
        }
        $CurrentStep = 'ActiveStoreReadback'
        if (-not (Test-TrialRules $State)) { throw 'Complete active-rule readback failed.' }
    } catch {
        $Detail = $_.Exception.Message
        $Protection = 'Do not start RustDesk.'
        try {
            $Allow = Get-NetFirewallRule -PolicyStore PersistentStore -Name $AllowName -ErrorAction SilentlyContinue
            if ($Allow -and (Test-TrialRule $Allow $Specs[0] -AllowDisabled)) {
                Disable-NetFirewallRule -PolicyStore PersistentStore -Name $AllowName -ErrorAction Stop | Out-Null
                $Protection = 'Owned direct Allow disabled; do not start RustDesk.'
            }
        } catch { $Protection = 'Could not confirm direct Allow disabled; do not start RustDesk.' }
        throw "Firewall repair failed at ${CurrentStep}: $Detail $Protection"
    }
}

function Assert-Config($State, [string]$Path = $ConfigPath) {
    Assert-NativeStorage $Path
    $Text = [IO.File]::ReadAllText($Path)
    if ([regex]::Matches($Text, '(?m)^\s*\[options\]\s*$').Count -ne 1) { throw 'Expected one RustDesk options table.' }
    $Expected = @{
        'direct-server' = 'Y'; 'direct-access-port' = '21118'; 'stop-service' = 'N'
        'whitelist' = ($State.RemoteIps -join ','); 'approve-mode' = 'password'
        'verification-method' = 'use-temporary-password'; 'temporary-password-length' = '10'
        'custom-rendezvous-server' = '127.0.0.1:9'; 'relay-server' = '127.0.0.1:9'
        'api-server' = 'http://127.0.0.1:9'; 'access-mode' = 'custom'
        'enable-keyboard' = 'Y'; 'enable-clipboard' = 'Y'
    }
    foreach ($Line in [IO.File]::ReadAllLines($TemplatePath)) {
        if ($Line -match "^([a-z][a-z0-9-]+) = 'N'$" ) { $Expected[$Matches[1]] = 'N' }
    }
    foreach ($Key in $Expected.Keys) {
        $Pattern = '(?m)^\s*' + [regex]::Escape($Key) + '\s*=\s*[''\"]' + [regex]::Escape($Expected[$Key]) + '[''\"]\s*$'
        $Assignment = '(?m)^\s*' + [regex]::Escape($Key) + '\s*='
        if ([regex]::Matches($Text, $Assignment).Count -ne 1 -or [regex]::Matches($Text, $Pattern).Count -ne 1) {
            throw "Unsafe, duplicate or missing RustDesk option: $Key"
        }
    }
}

function Write-StagedConfig($State) {
    $StageDir = Split-Path -Parent $StagePath
    if (-not (Test-Path -LiteralPath $StageDir)) { New-Item -ItemType Directory -Path $StageDir | Out-Null }
    $Config = [IO.File]::ReadAllText($TemplatePath).Replace('__MOBILE_IPV4_ALLOWLIST__', ($State.RemoteIps -join ','))
    [IO.File]::WriteAllText($StagePath, $Config, $Utf8)
    Assert-Config $State -Path $StagePath
    $State | Add-Member -NotePropertyName StagedConfigHash -NotePropertyValue (Get-FileHash -LiteralPath $StagePath).Hash -Force
}

function Initialize-NativeConfig($State) {
    Assert-UnpackagedContext
    if ($State.ConfigRoot -ne $ConfigRoot -or $State.ConfigPath -ne $ConfigPath) { throw 'Native profile path or user context changed.' }
    Assert-Config $State -Path $StagePath
    if ((Get-FileHash -LiteralPath $StagePath).Hash -ne $State.StagedConfigHash) { throw 'Staged configuration hash changed.' }
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        Assert-RustDeskStopped
        $RootExisted = Test-Path -LiteralPath $ConfigRoot
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $ConfigPath))) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $ConfigPath) | Out-Null
        }
        if (-not $RootExisted) { Set-Acl -LiteralPath $ConfigRoot -AclObject (Get-Acl -LiteralPath $TrialRoot) }
        $Bytes = [IO.File]::ReadAllBytes($StagePath)
        $Stream = New-Object IO.FileStream($ConfigPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $Stream.Write($Bytes, 0, $Bytes.Length); $Stream.Flush($true) } finally { $Stream.Dispose() }
        $Acl = New-Object Security.AccessControl.FileSecurity
        $Acl.SetAccessRuleProtection($true, $false)
        foreach ($Sid in @($State.OwnerSid, 'S-1-5-18', 'S-1-5-32-544')) {
            $Acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
                ([Security.Principal.SecurityIdentifier]$Sid), 'FullControl', 'Allow')))
        }
        Set-Acl -LiteralPath $ConfigPath -AclObject $Acl
        $State | Add-Member -NotePropertyName NativeRootCreated -NotePropertyValue (-not $RootExisted) -Force
        $State.ConfigExistedBefore = $RootExisted
    } elseif ('NativeRootCreated' -notin $State.PSObject.Properties.Name) {
        $State | Add-Member -NotePropertyName NativeRootCreated -NotePropertyValue $false
        $State.ConfigExistedBefore = $true
    }
    # Verify the real handle after creation; a logical path alone is not proof.
    Assert-Config $State
    $State | Add-Member -NotePropertyName NativeConfigPath -NotePropertyValue (Get-StoragePath $ConfigPath) -Force
    $State | Add-Member -NotePropertyName NativeConfigHash -NotePropertyValue (Get-FileHash -LiteralPath $ConfigPath).Hash -Force
    $State | Add-Member -NotePropertyName NativeConfigVerifiedAt -NotePropertyValue ([DateTimeOffset]::Now.ToString('o')) -Force
    [IO.File]::WriteAllText($StatePath, ($State | ConvertTo-Json -Depth 5), $Utf8)
}

if ($Action -eq 'Prepare') {
    Assert-Binaries
    if (Test-Path -LiteralPath $StatePath) { throw 'Already prepared; verify instead of overwriting.' }
    if (@(Get-Process -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0 -or
        @(Get-Service -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Existing RustDesk instance detected.' }
    $Tail = Get-TailContext
    $State = [pscustomobject]@{
        Version = '1.5.0'; PreparedAt = [DateTimeOffset]::Now.ToString('o')
        OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        ConfigRoot = $ConfigRoot; ConfigPath = $ConfigPath; ConfigExistedBefore = $null
        LocalIp = $Tail.LocalIp; RemoteIps = $Tail.RemoteIps; DshProfileHashes = @(Get-DesktopHashes)
        FirewallApplied = $false; MobileAcceptance = 'pending'
    }
    Write-StagedConfig $State
    [IO.File]::WriteAllText($StatePath, ($State | ConvertTo-Json -Depth 5), $Utf8)
    Write-Output 'Prepared F-drive staging only. Native profile, firewall, and mobile acceptance are pending.'
    exit 0
}

$State = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne $State.OwnerSid) {
    throw 'Run as the same Windows account that prepared this trial.'
}

if ($Action -eq 'Stage') {
    Assert-Binaries
    Write-StagedConfig $State
    [IO.File]::WriteAllText($StatePath, ($State | ConvertTo-Json -Depth 5), $Utf8)
    Write-Output 'Staged config on F drive. No native AppData writes or firewall changes.'
    exit 0
}

if ($Action -in @('Firewall', 'RemoveFirewall')) {
    if (-not (Test-Admin)) { throw 'This action needs normal Windows UAC elevation.' }
    Assert-UnpackagedContext
    Assert-Binaries
    if ($Action -eq 'Firewall') {
        $Tail = Get-TailContext
        if ($Tail.LocalIp -ne $State.LocalIp -or -not (Test-SameSet $Tail.RemoteIps $State.RemoteIps)) {
            throw 'Tailscale peer addresses changed; inspect instead of widening the allowlist.'
        }
        $Profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
        if (@($Profiles | Where-Object { -not $_.Enabled -or $_.DefaultInboundAction -ne 'Block' -or -not $_.AllowInboundRules }).Count -gt 0) {
            throw 'Active Windows firewall must be enabled with default inbound blocking and rules permitted.'
        }
        Initialize-NativeConfig $State
        Set-TrialFirewall $State
        $State.FirewallApplied = $true
    } else {
        if (@(Get-Process -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Exit RustDesk normally before removing protection.' }
        $OwnedRules = @()
        foreach ($Spec in @(Get-RuleSpecs $State)) {
            $Rule = Get-NetFirewallRule -Name ($RulePrefix + $Spec.Suffix) -ErrorAction SilentlyContinue
            if ($Rule) {
                $App = $Rule | Get-NetFirewallApplicationFilter
                if ($Rule.Group -ne $RuleGroup -or $App.Program -ne $ExePath) { throw 'Rule ownership mismatch.' }
                $OwnedRules += $Rule
            }
        }
        # Validate all targets before the first mutation, then read back both stores.
        foreach ($Rule in $OwnedRules) { $Rule | Remove-NetFirewallRule -ErrorAction Stop }
        if (@(Get-NetFirewallRule -Name ($RulePrefix + '*') -ErrorAction SilentlyContinue).Count -gt 0 -or
            @(Get-NetFirewallRule -PolicyStore ActiveStore -Name ($RulePrefix + '*') -ErrorAction SilentlyContinue).Count -gt 0) {
            throw 'Owned firewall rules remain; do not archive the program.'
        }
        $State.FirewallApplied = $false
    }
    [IO.File]::WriteAllText($StatePath, ($State | ConvertTo-Json -Depth 5), $Utf8)
    Write-Output ('Firewall action completed: ' + $Action)
    exit 0
}

if ($Action -eq 'ArchiveConfig') {
    Assert-UnpackagedContext
    if (@(Get-Process -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Exit RustDesk normally first.' }
    if (@(Get-NetFirewallRule -Name ($RulePrefix + '*') -ErrorAction SilentlyContinue).Count -gt 0) { throw 'Remove owned firewall rules first.' }
    if ('NativeRootCreated' -notin $State.PSObject.Properties.Name -or -not $State.NativeRootCreated -or
        $State.ConfigExistedBefore -or $State.ConfigRoot -ne $ConfigRoot) { throw 'Config ownership mismatch; preserve existing user data.' }
    $Archive = Join-Path $TrialRoot ('retired-config-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $Source = (Resolve-Path -LiteralPath $ConfigRoot).Path
    if ($Source -ne $ConfigRoot -or (Test-Path -LiteralPath $Archive) -or
        -not [IO.Path]::GetFullPath($Archive).StartsWith($TrialRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive path.' }
    Move-Item -LiteralPath $Source -Destination $Archive
    Write-Output 'New trial config archived recoverably; Tailscale, DSH, and all sessions untouched.'
    exit 0
}

Assert-Binaries
Assert-Config $State
$Tail = Get-TailContext
$Processes = @(Get-Process -Name '*RustDesk*' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $ExePath })
$PidList = @($Processes | Select-Object -ExpandProperty Id)
$Listeners = @(Get-NetTCPConnection -State Listen -LocalPort 21118 -ErrorAction SilentlyContinue |
    Where-Object { $_.OwningProcess -in $PidList })
$Connections = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
    Where-Object { $_.OwningProcess -in $PidList })
$BadConnections = @($Connections | Where-Object { $_.RemoteAddress -notin (@($State.LocalIp, '127.0.0.1', '::1') + @($State.RemoteIps)) })
$Result = [pscustomobject]@{
    PinnedBinariesAndRequiredOptionsMatch = $true; FirewallValid = (Test-TrialRules $State)
    TailAddressesMatch = ($Tail.LocalIp -eq $State.LocalIp -and (Test-SameSet $Tail.RemoteIps $State.RemoteIps))
    IpadOnline = @($Tail.Mobiles | Where-Object { $_.OS -eq 'iOS' -and $_.Online }).Count -gt 0
    AndroidOnline = @($Tail.Mobiles | Where-Object { $_.OS -eq 'android' -and $_.Online }).Count -gt 0
    RunningProcesses = $Processes.Count; DirectListeners = $Listeners.Count
    EstablishedAllowedMobileConnections = @($Connections | Where-Object { $_.RemoteAddress -in $State.RemoteIps }).Count
    EstablishedUnexpectedConnections = $BadConnections.Count
    RustDeskServices = @(Get-Service -Name '*RustDesk*' -ErrorAction SilentlyContinue).Count
    DshProfileUnchanged = ((@(Get-DesktopHashes) | ConvertTo-Json -Compress) -eq (@($State.DshProfileHashes) | ConvertTo-Json -Compress))
    ActualMobileAcceptance = $State.MobileAcceptance
}
[IO.File]::WriteAllText((Join-Path $TrialRoot 'verify-latest.json'), ($Result | ConvertTo-Json -Depth 5), $Utf8)
$Result | ConvertTo-Json -Depth 5
if (-not $Result.FirewallValid -or -not $Result.TailAddressesMatch -or $Result.EstablishedUnexpectedConnections -gt 0 -or
    $Result.RustDeskServices -gt 0 -or $Result.DirectListeners -eq 0) { exit 2 }
