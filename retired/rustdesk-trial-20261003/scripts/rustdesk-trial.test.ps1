Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Source = Join-Path $PSScriptRoot 'rustdesk-trial.ps1'
$TemplatePath = Join-Path $PSScriptRoot '..\config\remote\rustdesk-trial.toml'
$Tokens = $null
$Errors = $null
$Ast = [Management.Automation.Language.Parser]::ParseFile($Source, [ref]$Tokens, [ref]$Errors)
if (@($Errors).Count -gt 0) { throw 'Production script syntax failed.' }
$Selected = @('ConvertTo-IpNumber', 'ConvertFrom-IpNumber', 'Get-IpComplement', 'Get-RuleSpecs', 'Test-SameSet', 'Assert-Config', 'Get-StoragePath', 'Assert-NativeStorage', 'Initialize-NativeApi', 'Assert-UnpackagedContext', 'Assert-RustDeskStopped', 'Initialize-NativeConfig', 'Test-TrialRule', 'Test-TrialRules', 'Set-TrialFirewall')
foreach ($Definition in $Ast.FindAll({ param($Node) $Node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
    if ($Definition.Name -in $Selected) { . ([scriptblock]::Create($Definition.Extent.Text)) }
}

$Passed = 0
function Assert-Test([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAILED: $Name" }
    $script:Passed++
}
foreach ($Number in @([uint64]0, [uint64]1, [uint64]167772161, [uint64]4294967295)) {
    Assert-Test ((ConvertTo-IpNumber (ConvertFrom-IpNumber $Number)) -eq $Number) "IPv4 roundtrip $Number"
}
$Allowed = @('100.100.0.1', '100.100.0.3')
$Ranges = @(Get-IpComplement $Allowed)
Assert-Test ($Ranges.Count -eq 5 -and $Ranges[-2] -eq '::/1' -and $Ranges[-1] -eq '8000::/1') 'All IPv6 is explicitly blocked with two disjoint halves'
Assert-Test ($Ranges[0] -eq '0.0.0.0-100.100.0.0' -and $Ranges[1] -eq '100.100.0.2-100.100.0.2' -and
    $Ranges[2] -eq '100.100.0.4-255.255.255.255') 'Only exact allowlist addresses are holes'
Assert-Test ((@(Get-IpComplement @('0.0.0.0', '255.255.255.255')) -join ',') -eq '0.0.0.1-255.255.255.254,::/1,8000::/1') 'Boundary addresses do not overflow'
Assert-Test (Test-SameSet @('a','b','a') @('b','a')) 'Set comparison'
Assert-Test (-not (Test-SameSet @('a','b') @('b','c'))) 'Different sets rejected'
$State = [pscustomobject]@{ LocalIp = '100.100.0.10'; RemoteIps = $Allowed }
$Specs = @(Get-RuleSpecs $State)
Assert-Test ($Specs.Count -eq 4 -and @($Specs | Where-Object Action -eq 'Allow').Count -eq 1) 'One allow, three scoped blockers'
$Allow = $Specs[0]
Assert-Test ($Allow.Protocol -eq 'TCP' -and $Allow.LocalPort -eq '21118' -and $Allow.InterfaceAlias -eq 'Tailscale' -and
    (Test-SameSet $Allow.RemoteAddress $Allowed) -and $Allow.LocalAddress[0] -eq $State.LocalIp) 'Narrow incoming rule'
Assert-Test ($Specs[3].Direction -eq 'Outbound' -and $Specs[3].Action -eq 'Block' -and $Specs[3].Protocol -eq 'Any') 'Public outbound blocker'

# Native provider validates address prefixes before denying writes to this
# documented read-only store. No rule is added, even when this test fails.
function Get-NativeRuleValidationError($Spec) {
    $Params = @{} + $Spec
    $Params.Remove('Suffix')
    try {
        New-NetFirewallRule @Params -PolicyStore SystemDefaults -Name 'DSH-RustDeskTrial-AddressValidation' `
            -DisplayName 'Read-only address validation' -Program 'F:\Apps\RustDeskTrial\app\RustDesk.exe' `
            -Profile Any -Enabled False -ErrorAction Stop | Out-Null
        throw 'Unexpected success writing a read-only firewall store.'
    } catch { return $_.FullyQualifiedErrorId }
}
$BadPrefix = @{ Suffix = 'Control'; Direction = 'Inbound'; Action = 'Block'; Protocol = 'Any';
    LocalPort = 'Any'; LocalAddress = @('Any'); RemoteAddress = @('::/0'); InterfaceAlias = 'Any' }
Assert-Test ((Get-NativeRuleValidationError $BadPrefix) -like '*0x80070057*') 'Native provider rejects the original IPv6 /0 prefix'
foreach ($Spec in $Specs) {
    Assert-Test ((Get-NativeRuleValidationError $Spec) -eq 'Windows System Error 5,New-NetFirewallRule') `
        ('Native address validation passes before read-only denial: ' + $Spec.Suffix)
}
$RulePrefix = 'DSH-RustDeskTrial-20261003-'
$RuleGroup = 'DSH RustDesk private trial 20261003'
$ExePath = 'F:\Apps\RustDeskTrial\app\RustDesk.exe'
$PreparedState = [IO.File]::ReadAllText('F:\Apps\RustDeskTrial\trial-state.json') | ConvertFrom-Json
foreach ($Spec in @(Get-RuleSpecs $PreparedState)) {
    Assert-Test ((Get-NativeRuleValidationError $Spec) -eq 'Windows System Error 5,New-NetFirewallRule') `
        ('Exact prepared plan passes native address validation: ' + $Spec.Suffix)
}
$NativeAllow = Get-NetFirewallRule -PolicyStore ActiveStore -Name ($RulePrefix + 'AllowDirect') -ErrorAction SilentlyContinue
if ($NativeAllow) {
    Assert-Test (Test-TrialRule $NativeAllow @(Get-RuleSpecs $PreparedState)[0] -AllowDisabled) 'Actual native executable rule accepts its unset Package filter'
}

$FixtureRoot = Join-Path 'F:\Apps\RustDeskTrial' ('test-fixture-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $FixtureRoot | Out-Null
$ConfigPath = Join-Path $FixtureRoot 'RustDesk2.toml'
$Template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\config\remote\rustdesk-trial.toml'))
$GoodConfig = $Template.Replace('__MOBILE_IPV4_ALLOWLIST__', ($Allowed -join ','))
$Utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ConfigPath, $GoodConfig, $Utf8)
Assert-Config $State
Assert-Test $true 'Expected seed options pass'
$Cases = @(
    @("direct-server = 'Y'", "direct-server = 'N'"),
    @("whitelist = '100.100.0.1,100.100.0.3'", "whitelist = '100.64.0.0/10'"),
    @("approve-mode = 'password'", "approve-mode = 'click'"),
    @("enable-file-transfer = 'N'", "enable-file-transfer = 'Y'"),
    @("temporary-password-length = '10'", "temporary-password-length = '6'"),
    @("custom-rendezvous-server = '127.0.0.1:9'", "custom-rendezvous-server = 'example.test:21116'"),
    @("allow-remote-config-modification = 'N'", "allow-remote-config-modification = 'Y'"),
    @("stop-service = 'N'", "stop-service = 'Y'"),
    @("[options]", "[different-table]"),
    @("approve-mode = 'password'", "approve-mode = 'password'`napprove-mode = 'click'")
)
foreach ($Case in $Cases) {
    [IO.File]::WriteAllText($ConfigPath, $GoodConfig.Replace($Case[0], $Case[1]), $Utf8)
    $Rejected = $false
    try { Assert-Config $State } catch { $Rejected = $true }
    Assert-Test $Rejected ('Unsafe config rejected: ' + $Case[0].Split('=')[0].Trim())
}
[IO.File]::WriteAllText($ConfigPath, $GoodConfig, $Utf8)
[string]$VirtualConfigPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'RustDesk\config\RustDesk2.toml'
if ((Test-Path -LiteralPath $VirtualConfigPath) -and
    -not [string]::Equals((Get-StoragePath $VirtualConfigPath), [IO.Path]::GetFullPath($VirtualConfigPath), [StringComparison]::OrdinalIgnoreCase)) {
    $PreparedState = [IO.File]::ReadAllText('F:\Apps\RustDeskTrial\trial-state.json') | ConvertFrom-Json
    $ConfigPath = $VirtualConfigPath
    $Rejected = $false
    try { Assert-Config $PreparedState } catch { $Rejected = $true }
    Assert-Test $Rejected 'Codex redirected AppData must not count as native RustDesk config'
    $Rejected = $false
    try { Assert-UnpackagedContext } catch { $Rejected = $true }
    Assert-Test $Rejected 'Native setup rejects actual redirected storage even without reported package identity'
}

# Filesystem integration uses a new F-drive fixture, not any native AppData.
function Assert-UnpackagedContext { }
function Assert-RustDeskStopped { }
$TrialRoot = 'F:\Apps\RustDeskTrial'
$StagePath = Join-Path $FixtureRoot 'staged.toml'
[IO.File]::WriteAllText($StagePath, $GoodConfig, $Utf8)
$StatePath = Join-Path $FixtureRoot 'fixture-state.json'
$ConfigRoot = Join-Path $FixtureRoot 'native-profile'
$ConfigPath = Join-Path $ConfigRoot 'config\RustDesk2.toml'
$NativeState = [pscustomobject]@{
    ConfigRoot = $ConfigRoot; ConfigPath = $ConfigPath; ConfigExistedBefore = $null
    OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    RemoteIps = $Allowed; StagedConfigHash = (Get-FileHash -LiteralPath $StagePath).Hash
}
Initialize-NativeConfig $NativeState
Assert-Test ((Test-Path -LiteralPath $ConfigPath) -and $NativeState.NativeRootCreated) 'Missing native profile is initialized from F-drive staging'
Assert-Test ((Get-FileHash -LiteralPath $ConfigPath).Hash -eq $NativeState.StagedConfigHash) 'Native file exactly matches staged bytes'
Assert-Test ($NativeState.NativeConfigPath -eq $ConfigPath -and (Test-Path -LiteralPath $StatePath)) 'Physical path and persisted native proof'
$Before = (Get-FileHash -LiteralPath $ConfigPath).Hash
Initialize-NativeConfig $NativeState
Assert-Test ((Get-FileHash -LiteralPath $ConfigPath).Hash -eq $Before -and $NativeState.NativeRootCreated) 'Retry is idempotent and retains archive ownership'
[IO.File]::WriteAllText($ConfigPath, $GoodConfig.Replace("approve-mode = 'password'", "approve-mode = 'click'"), $Utf8)
$ExistingHash = (Get-FileHash -LiteralPath $ConfigPath).Hash
$Rejected = $false
try { Initialize-NativeConfig $NativeState } catch { $Rejected = $true }
Assert-Test ($Rejected -and (Get-FileHash -LiteralPath $ConfigPath).Hash -eq $ExistingHash) 'Existing incompatible config is refused without overwrite'
$NativeState.StagedConfigHash = 'changed'
$Rejected = $false
try { Initialize-NativeConfig $NativeState } catch { $Rejected = $true }
Assert-Test $Rejected 'Changed staged hash is refused'
[IO.File]::WriteAllText($ConfigPath, $GoodConfig, $Utf8)

# Run the real repair orchestrator with an isolated rule store and injected
# provider failures. These do not add, remove or enable Windows policy rules.
$StatePath = Join-Path $FixtureRoot 'firewall-state.json'
function New-FixtureRule($Spec, [string]$Name) {
    [pscustomobject]@{
        Name = $Name; Group = $RuleGroup; Profile = 'Any'; Enabled = 'True'
        Direction = $Spec.Direction; Action = $Spec.Action
        App = [pscustomobject]@{ Program = $ExePath; Package = $null }
        Port = [pscustomobject]@{ Protocol = $Spec.Protocol; LocalPort = @($Spec.LocalPort); RemotePort = @('Any') }
        Address = [pscustomobject]@{ LocalAddress = $Spec.LocalAddress; RemoteAddress = $Spec.RemoteAddress }
        Interface = [pscustomobject]@{ InterfaceAlias = @($Spec.InterfaceAlias) }
        Service = [pscustomobject]@{ Service = 'Any' }
    }
}
function Get-NetFirewallRule {
    [CmdletBinding()] param([string]$PolicyStore, [string]$Name)
    foreach ($Rule in @($script:FixtureRules.Values | Where-Object Name -Like $Name)) {
        if ($PolicyStore -eq 'ActiveStore' -and $script:ReadbackMismatch -and $Rule.Action -eq 'Block') {
            $Altered = $Rule.PSObject.Copy()
            $Altered.Group = 'Unexpected active policy'
            $Altered
        } else { $Rule }
    }
}
function Get-NetFirewallApplicationFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { $InputObject.App } }
function Get-NetFirewallPortFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { $InputObject.Port } }
function Get-NetFirewallAddressFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { $InputObject.Address } }
function Get-NetFirewallInterfaceFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { $InputObject.Interface } }
function Get-NetFirewallServiceFilter { param([Parameter(ValueFromPipeline)]$InputObject) process { $InputObject.Service } }
function New-NetFirewallRule {
    [CmdletBinding()] param([string]$PolicyStore, [string]$Name, [string]$DisplayName, [string]$Group,
        [string]$Program, [string]$Profile, [string]$Enabled, [string]$Direction, [string]$Action,
        [string]$Protocol, [string]$LocalPort, [string[]]$LocalAddress, [string[]]$RemoteAddress, [string]$InterfaceAlias)
    if ($PolicyStore -ne 'PersistentStore' -or $PSBoundParameters['ErrorAction'] -ne 'Stop') { throw 'Wrong store or missing fail-fast behavior.' }
    $script:RepairLog.Add('Create:' + $Name) | Out-Null
    if ($Name -eq ($RulePrefix + $script:FailureSuffix)) { Write-Error 'Injected native provider failure'; return }
    $Spec = @{ Direction = $Direction; Action = $Action; Protocol = $Protocol; LocalPort = $LocalPort;
        LocalAddress = $LocalAddress; RemoteAddress = $RemoteAddress; InterfaceAlias = $InterfaceAlias }
    $Rule = New-FixtureRule $Spec $Name
    $script:FixtureRules[$Name] = $Rule
    $Rule
}
function Disable-NetFirewallRule {
    [CmdletBinding()] param([string]$PolicyStore, [string]$Name)
    $script:RepairLog.Add('Disable:' + $Name) | Out-Null
    $script:FixtureRules[$Name].Enabled = 'False'
}
function Enable-NetFirewallRule {
    [CmdletBinding()] param([string]$PolicyStore, [string]$Name)
    $script:RepairLog.Add('Enable:' + $Name) | Out-Null
    $script:FixtureRules[$Name].Enabled = 'True'
}
function Assert-RustDeskStopped { if ($script:FixtureRunning) { throw 'Fixture RustDesk is still running.' } }
function Reset-FirewallFixture {
    $script:FixtureRules = @{}
    $script:RepairLog = New-Object 'Collections.Generic.List[string]'
    $script:FailureSuffix = $null
    $script:ReadbackMismatch = $false
    $script:FixtureRunning = $false
    $script:RepairState = [pscustomobject]@{ LocalIp = $State.LocalIp; RemoteIps = $State.RemoteIps; FirewallApplied = $true }
}
Reset-FirewallFixture
Set-TrialFirewall $RepairState
Assert-Test (Test-TrialRules $RepairState) 'Clean repair creates four exact rules'
Assert-Test ($RepairLog.Count -eq 4 -and $RepairLog[-1] -eq ('Create:' + $RulePrefix + 'AllowDirect')) 'All blockers are created before direct Allow'

Reset-FirewallFixture
$FixtureRules[$RulePrefix + 'AllowDirect'] = New-FixtureRule $Specs[0] ($RulePrefix + 'AllowDirect')
Set-TrialFirewall $RepairState
Assert-Test (Test-TrialRules $RepairState) 'User partial state with only native Allow is repaired'
Assert-Test ($RepairLog[0] -eq ('Disable:' + $RulePrefix + 'AllowDirect') -and
    $RepairLog[-1] -eq ('Enable:' + $RulePrefix + 'AllowDirect')) 'Partial Allow remains disabled until blockers are complete'
$BeforeCount = $FixtureRules.Count
$RepairLog.Clear()
Set-TrialFirewall $RepairState
Assert-Test ($FixtureRules.Count -eq $BeforeCount -and @($RepairLog | Where-Object { $_ -like 'Create:*' }).Count -eq 0) 'Repeat repair creates no duplicate rules'

Reset-FirewallFixture
$FixtureRules[$RulePrefix + 'AllowDirect'] = New-FixtureRule $Specs[0] ($RulePrefix + 'AllowDirect')
$FailureSuffix = 'BlockOtherDestinations'
$Rejected = $false
try { Set-TrialFirewall $RepairState } catch { $Rejected = $_.Exception.Message -like '*BlockOtherDestinations*Injected native provider failure*' }
Assert-Test ($Rejected -and $FixtureRules[$RulePrefix + 'AllowDirect'].Enabled -eq 'False' -and
    -not $RepairState.FirewallApplied) 'Provider failure is named, fail-fast, and leaves Allow disabled'
Assert-Test (-not $FixtureRules.ContainsKey($RulePrefix + 'BlockPublicOutbound') -and
    @($RepairLog | Where-Object { $_ -like 'Enable:*' }).Count -eq 0) 'Failure does not continue or restore Allow'
$FailureSuffix = $null
Set-TrialFirewall $RepairState
Assert-Test (Test-TrialRules $RepairState) 'Retry safely fills remaining rules after injected failure'

Reset-FirewallFixture
$ReadbackMismatch = $true
$Rejected = $false
try { Set-TrialFirewall $RepairState } catch { $Rejected = $_.Exception.Message -like '*ActiveStoreReadback*' }
Assert-Test ($Rejected -and $FixtureRules[$RulePrefix + 'AllowDirect'].Enabled -eq 'False') 'Active readback mismatch disables owned direct Allow'

foreach ($Collision in @('group', 'program', 'package', 'remote-port', 'remote-address', 'unexpected-name')) {
    Reset-FirewallFixture
    $Rule = New-FixtureRule $Specs[0] ($RulePrefix + 'AllowDirect')
    switch ($Collision) {
        'group' { $Rule.Group = 'Unrelated owner' }
        'program' { $Rule.App.Program = 'C:\Unrelated.exe' }
        'package' { $Rule.App.Package = 'S-1-15-2-123' }
        'remote-port' { $Rule.Port.RemotePort = @('443') }
        'remote-address' { $Rule.Address.RemoteAddress = @('Any') }
        'unexpected-name' { $Rule.Name = $RulePrefix + 'Unrelated' }
    }
    $FixtureRules[$Rule.Name] = $Rule
    $Before = $Rule | ConvertTo-Json -Depth 5 -Compress
    $Rejected = $false
    try { Set-TrialFirewall $RepairState } catch { $Rejected = $_.Exception.Message -like 'Conflicting trial rule*' }
    Assert-Test ($Rejected -and $RepairLog.Count -eq 0 -and $Before -eq ($Rule | ConvertTo-Json -Depth 5 -Compress)) ('Collision is refused without changes: ' + $Collision)
}
Reset-FirewallFixture
$FixtureRunning = $true
$Rejected = $false
try { Set-TrialFirewall $RepairState } catch { $Rejected = $true }
Assert-Test ($Rejected -and $RepairLog.Count -eq 0) 'Running RustDesk refuses repair before policy mutation'

[pscustomobject]@{ Passed = $Passed; NativeAddressProviderValidationTested = $true;
    LiveFirewallRulesChanged = $false; NativeRustDeskOrMobileSessionTested = $false } | ConvertTo-Json
