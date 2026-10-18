# Portable PowerShell 7 tests for the read-only SysMain preflight.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\SysMainPreflight.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }

$supportedOs = [pscustomobject]@{ editionId='Professional'; build='26300'; updateRevision=9711; architecture='X64' }
function New-Providers {
    param([object]$Os=$supportedOs,[object]$Service=$null,[object]$Registry=$null,[object]$Relationships=$null,
          [scriptblock]$OsProvider,[scriptblock]$ServiceProvider,[scriptblock]$RegistryProvider,[scriptblock]$RelationshipsProvider)
    if ($null -eq $Service) { $Service=[pscustomobject]@{found=$true;name='SysMain';state='Running';startMode='Auto';processId=2032} }
    if ($null -eq $Registry) { $Registry=[pscustomobject]@{keyExists=$true;start=[pscustomobject]@{exists=$true;kind='DWord';value=[uint32]2};delayedAutoStart=[pscustomobject]@{exists=$false;kind=$null;value=$null}} }
    if ($null -eq $Relationships) { $Relationships=[pscustomobject]@{dependencies=[string[]]@('RpcSs','FileInfo');dependents=[string[]]@()} }
    [ordered]@{
        os = if ($OsProvider) { $OsProvider } else { { $Os }.GetNewClosure() }
        service = if ($ServiceProvider) { $ServiceProvider } else { { $Service }.GetNewClosure() }
        registry = if ($RegistryProvider) { $RegistryProvider } else { { $Registry }.GetNewClosure() }
        relationships = if ($RelationshipsProvider) { $RelationshipsProvider } else { { $Relationships }.GetNewClosure() }
    }
}

$normal = Get-UindosSysMainPreflight -Providers (New-Providers)
Assert-Test ($normal.schema -eq 'uindos.sysmain-preflight/v1' -and $normal.collection -eq 'injected-test-providers:complete') 'Schema and complete supported observation'
Assert-Test ($normal.platform.edition -eq 'Windows 11 Pro' -and $normal.platform.build.full -eq '26300.9711') 'Exact Windows build and UBR are retained'
Assert-Test ($normal.service.name -eq 'SysMain' -and $normal.service.state -eq 'Running' -and $normal.service.startMode -eq 'Auto' -and $normal.service.processId -eq 2032) 'Only sanitized SysMain service fields are reported'
Assert-Test ($normal.registry.start.value -eq 2 -and -not $normal.registry.delayedAutoStart.exists -and $null -eq $normal.registry.delayedAutoStart.value) 'Exact Start value and DelayedAutoStart absence are preserved'
Assert-Test ($normal.relationships.dependencies -contains 'RpcSs' -and $normal.relationships.dependents.Count -eq 0 -and $normal.consistency -eq 'consistent') 'Immediate dependencies, dependents and SCM/registry consistency are reported'
Assert-Test ($normal.PSObject.Properties.Name -notcontains 'safeToDisable' -and $normal.PSObject.Properties.Name -notcontains 'authorization') 'No readiness or authorization claim is exposed'

$delayedRegistry=[pscustomobject]@{keyExists=$true;start=[pscustomobject]@{exists=$true;kind='DWord';value=[uint32]2};delayedAutoStart=[pscustomobject]@{exists=$true;kind='DWord';value=[uint32]1}}
$delayed=Get-UindosSysMainPreflight -Providers (New-Providers -Registry $delayedRegistry)
Assert-Test ($delayed.registry.delayedAutoStart.exists -and $delayed.registry.delayedAutoStart.value -eq 1 -and $delayed.collection -eq 'injected-test-providers:complete') 'Present delayed-start DWORD is preserved'

$unsupported=Get-UindosSysMainPreflight -Providers (New-Providers -Os ([pscustomobject]@{editionId='Enterprise';build='26300';updateRevision=9711;architecture='X64'}))
Assert-Test ($unsupported.platform.status -eq 'unsupported' -and $unsupported.collection -eq 'injected-test-providers:unsupported') 'Unsupported Windows edition is not reported complete'
$badBuild=Get-UindosSysMainPreflight -Providers (New-Providers -Os ([pscustomobject]@{editionId='Professional';build='not-a-build';updateRevision=9711;architecture='X64'}))
Assert-Test ($badBuild.platform.status -eq 'error' -and $badBuild.collection -ne 'injected-test-providers:complete') 'Malformed build cannot pass applicability'
$nonWindows=Get-UindosSysMainPreflight -TestNonWindows
Assert-Test ($nonWindows.platform.status -eq 'unsupported' -and $nonWindows.collection -eq 'unsupported' -and $nonWindows.probes.service -eq 'unsupported') 'Non-Windows platform is unsupported and performs no native collection'

$missing=Get-UindosSysMainPreflight -Providers (New-Providers -Service ([pscustomobject]@{found=$false}))
Assert-Test ($missing.probes.service -eq 'not-found' -and $missing.collection -ne 'injected-test-providers:complete') 'Missing SysMain service is distinct from an empty successful inventory'
$serviceMismatch=Get-UindosSysMainPreflight -Providers (New-Providers -Service ([pscustomobject]@{found=$true;name='OtherSvc';state='Running';startMode='Auto';processId=1}))
Assert-Test ($serviceMismatch.probes.service -eq 'error' -and $null -eq $serviceMismatch.service) 'Unexpected service identity is rejected'

$providerFailure=Get-UindosSysMainPreflight -Providers (New-Providers -ServiceProvider { throw 'private device C:\Users\Secret\one' })
Assert-Test ($providerFailure.probes.service -eq 'error' -and $providerFailure.collection -ne 'injected-test-providers:complete') 'Provider failure remains error, not empty success'
$missingProviderSet=New-Providers
$missingProviderSet.Remove('registry')
$missingProvider=Get-UindosSysMainPreflight -Providers $missingProviderSet
Assert-Test ($missingProvider.probes.registry -eq 'not-collected' -and $missingProvider.collection -ne 'injected-test-providers:complete') 'Missing provider cannot pass complete collection'

$wrongTypeRegistry=[pscustomobject]@{keyExists=$true;start=[pscustomobject]@{exists=$true;kind='String';value='2'};delayedAutoStart=[pscustomobject]@{exists=$false;kind=$null;value=$null}}
$wrongType=Get-UindosSysMainPreflight -Providers (New-Providers -Registry $wrongTypeRegistry)
Assert-Test ($wrongType.probes.registry -eq 'error' -and $wrongType.collection -ne 'injected-test-providers:complete') 'Non-DWORD Start is rejected'
$wrongDelayed=[pscustomobject]@{keyExists=$true;start=[pscustomobject]@{exists=$true;kind='DWord';value=[uint32]2};delayedAutoStart=[pscustomobject]@{exists=$true;kind='DWord';value=[uint32]2}}
$badDelayed=Get-UindosSysMainPreflight -Providers (New-Providers -Registry $wrongDelayed)
Assert-Test ($badDelayed.probes.registry -eq 'error') 'DelayedAutoStart values outside zero or one are rejected'
$floatRegistry=[pscustomobject]@{keyExists=$true;start=[pscustomobject]@{exists=$true;kind='DWord';value=[double]2};delayedAutoStart=[pscustomobject]@{exists=$false;kind=$null;value=$null}}
$floatResult=Get-UindosSysMainPreflight -Providers (New-Providers -Registry $floatRegistry)
Assert-Test ($floatResult.probes.registry -eq 'error') 'A floating-point value cannot impersonate a DWORD'
$oversizePid=Get-UindosSysMainPreflight -Providers (New-Providers -Service ([pscustomobject]@{found=$true;name='SysMain';state='Running';startMode='Auto';processId=[uint64]4294967296}))
Assert-Test ($oversizePid.probes.service -eq 'error') 'Process identifier outside the native DWORD range is rejected'
$osDenied=Get-UindosSysMainPreflight -Providers (New-Providers -OsProvider {throw [UnauthorizedAccessException]::new('private')})
Assert-Test ($osDenied.platform.status -eq 'access-denied' -and $osDenied.collection -ne 'injected-test-providers:complete') 'OS collection failure is reflected in platform status'
$inconsistent=Get-UindosSysMainPreflight -Providers (New-Providers -Registry ([pscustomobject]@{keyExists=$true;start=[pscustomobject]@{exists=$true;kind='DWord';value=[uint32]3};delayedAutoStart=[pscustomobject]@{exists=$false;kind=$null;value=$null}}))
Assert-Test ($inconsistent.consistency -eq 'inconsistent' -and $inconsistent.collection -eq 'injected-test-providers:error') 'SCM and registry disagreement cannot pass complete collection'

$json=ConvertTo-Json -InputObject @($normal,$providerFailure,$serviceMismatch) -Depth 8 -Compress
foreach($secret in @('C:\Users\Secret','private device','PathName','StartName','BinaryPath','Exception')) { Assert-Test (-not $json.Contains($secret)) "Serialized report excludes private service/provider detail: $secret" }
Assert-Test ($normal.limitations -join ' ' -match '26300.9711') 'VM-tested build scope is explicit'
Write-Output 'PASS: SysMain preflight applicability, exact state, missing/error data, type/drift guards and privacy'
