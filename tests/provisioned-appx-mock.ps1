# Dependency-free cross-platform tests: only injected readers and JSON fixtures.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Probes.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$script:fallbackCalls = 0
$direct = {
    [pscustomobject]@{ DisplayName = 'Microsoft.ZuneMusic'; Version = '11.2512.10.0' }
    [pscustomobject]@{ DisplayName = 'Clipchamp.Clipchamp'; Version = '4.5.10920.0' }
}
$neverFallback = { $script:fallbackCalls++; throw 'Fallback should not execute.' }
$rows = @(Get-UindosProvisionedAppx -PrimaryReader $direct -FallbackReader $neverFallback -SkipPlatformChecks)
Assert-Test ($rows.Count -eq 2) 'direct result includes two packages'
Assert-Test ($rows[0].name -eq 'Clipchamp.Clipchamp') 'direct result sorted'
Assert-Test ($script:fallbackCalls -eq 0) 'successful direct query does not use fallback'

$registrationError = {
    throw [System.Runtime.InteropServices.COMException]::new('Class not registered', -2147221164)
}
$workingFallback = {
    $script:fallbackCalls++
    [pscustomobject]@{ name = 'Microsoft.BingNews'; version = '4.11.6001.0' }
}
$rows = @(Get-UindosProvisionedAppx -PrimaryReader $registrationError -FallbackReader $workingFallback -SkipPlatformChecks)
Assert-Test ($rows.Count -eq 1 -and $rows[0].name -eq 'Microsoft.BingNews') 'REGDB_E_CLASSNOTREG fallback works'
Assert-Test ($script:fallbackCalls -eq 1) 'fallback called only for exact COM error'

$otherError = { throw [System.InvalidOperationException]::new('Generic failure') }
$failed = $false
try { [void](Get-UindosProvisionedAppx -PrimaryReader $otherError -FallbackReader $workingFallback -SkipPlatformChecks) }
catch [System.InvalidOperationException] { $failed = $true }
Assert-Test ($failed -and $script:fallbackCalls -eq 1) 'generic failures are not hidden by fallback'

$wrongCom = { throw [System.Runtime.InteropServices.COMException]::new('Different COM failure', -2147024891) }
$failed = $false
try { [void](Get-UindosProvisionedAppx -PrimaryReader $wrongCom -FallbackReader $workingFallback -SkipPlatformChecks) }
catch [System.Runtime.InteropServices.COMException] { $failed = $true }
Assert-Test ($failed -and $script:fallbackCalls -eq 1) 'other COM errors never trigger fallback'

$badFallback = { throw [System.InvalidOperationException]::new('Fallback failed') }
$failed = $false
try { [void](Get-UindosProvisionedAppx -PrimaryReader $registrationError -FallbackReader $badFallback -SkipPlatformChecks) }
catch [System.InvalidOperationException] { $failed = $true }
Assert-Test $failed 'fallback failure is surfaced, not treated as empty list'

$empty = @(Get-UindosProvisionedAppx -PrimaryReader { @() } -FallbackReader $neverFallback -SkipPlatformChecks)
Assert-Test ($empty.Count -eq 0) 'valid empty provisioned inventory is supported'

$validJson = '{"schema":"uindos.provisioned-appx/v1","packages":[{"name":"Microsoft.ZuneMusic","version":"11.2512.10.0"},{"name":"Clipchamp.Clipchamp","version":"4.5.10920.0"}]}'
$parsed = @(ConvertFrom-UindosProvisionedAppxJson -Json $validJson)
Assert-Test ($parsed.Count -eq 2 -and $parsed[0].name -eq 'Clipchamp.Clipchamp') 'JSON payload validated, converted, sorted'
Assert-Test (@(ConvertFrom-UindosProvisionedAppxJson -Json '{"schema":"uindos.provisioned-appx/v1","packages":[]}').Count -eq 0) 'empty JSON list accepted'

foreach ($bad in @(
    '{}',
    '{"schema":"unexpected","packages":[]}',
    '{"schema":"uindos.provisioned-appx/v1","packages":null}',
    '{"schema":"uindos.provisioned-appx/v1","packages":[{"name":"../../escape","version":"1.2.3.4"}]}',
    '{"schema":"uindos.provisioned-appx/v1","packages":[{"name":"Valid.Name","version":"not-a-version"}]}',
    'not-json'
)) {
    $failed = $false
    try { [void](ConvertFrom-UindosProvisionedAppxJson -Json $bad) }
    catch { $failed = $true }
    Assert-Test $failed 'malformed or mismatched child payload rejected'
}
$failed = $false
try {
    [void](Get-UindosProvisionedAppx -PrimaryReader { [pscustomobject]@{ DisplayName = 'Invalid/Name'; Version = '1.2.3.4' } } -FallbackReader $neverFallback -SkipPlatformChecks)
}
catch [System.IO.InvalidDataException] { $failed = $true }
Assert-Test $failed 'invalid direct record rejected too'
Write-Output 'PASS: provisioned-AppX primary, targeted COM fallback, strict JSON validation, failure handling'
