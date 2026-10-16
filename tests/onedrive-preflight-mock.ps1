# Portable PowerShell 7 mocks; no Windows APIs, registry, filesystem or network.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\OneDrivePreflight.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$supportedOs = [pscustomobject]@{ editionId='Professional'; build='26300'; architecture='X64' }
$privatePath = 'C:\Users\Private Person\OneDrive - Private Org'
$privateCommand = '"C:\Users\Private Person\AppData\Local\Microsoft\OneDrive\OneDriveSetup.exe" /uninstall --account=secret-token'
function New-Providers {
    param([object[]]$Machine64=@(), [object[]]$Machine32=@(), [object[]]$Current64=@(), [object[]]$Current32=@(),
          [bool]$Running=$false, [bool]$Configured=$false, [string[]]$Roots=@(),
          [string]$Desktop='C:\Users\Person\Desktop', [string]$Documents='C:\Users\Person\Documents',
          [string]$Pictures='C:\Users\Person\Pictures', [scriptblock]$Machine32Provider,
          [scriptblock]$Machine64Provider)
    $providers = [ordered]@{
        os = { $supportedOs }.GetNewClosure()
        machine64 = if ($Machine64Provider) { $Machine64Provider } else { { [pscustomobject]@{ entries=[object[]]@($Machine64) } }.GetNewClosure() }
        machine32 = if ($Machine32Provider) { $Machine32Provider } else { { [pscustomobject]@{ entries=[object[]]@($Machine32) } }.GetNewClosure() }
        currentUser = { [pscustomobject]@{ entries=[object[]]@($Current64 + $Current32) } }.GetNewClosure()
        process = { [pscustomobject]@{ running=$Running } }.GetNewClosure()
        accounts = { [pscustomobject]@{ configured=$Configured; roots=@($Roots) } }.GetNewClosure()
        knownFolders = { [pscustomobject]@{ desktop=$Desktop; documents=$Documents; pictures=$Pictures } }.GetNewClosure()
    }
    return $providers
}
function New-Registration {
    param([string]$Publisher='Microsoft Corporation', [string]$Name='Microsoft OneDrive', [string]$Scope='machine64', [string]$Uninstall='')
    $entry = [pscustomobject]@{ displayName=$Name; publisher=$Publisher; uninstallString=$Uninstall; quietUninstallString='' }
    ConvertTo-UindosOneDriveRegistrationObservation -Entry $entry -Scope $Scope
}

# A clean, fully collected no-install result is absent; unconfigured account is separate evidence.
$absent = Get-UindosOneDrivePreflight -Providers (New-Providers)
Assert-Test ($absent.installation.status -eq 'absent') 'Complete empty registry views report absent'
Assert-Test ($absent.currentUserAccount.registryMetadata -eq 'not-observed') 'Absent account registry metadata is explicit'
Assert-Test ($absent.currentUserAccount.signInStatus -eq 'unknown') 'Sign-in remains unknown without account proof'
Assert-Test ($absent.filesOnDemand.status -eq 'unknown' -and $absent.assessment.uninstallReadiness -eq 'manual-review-required') 'Hydration and readiness remain unknown'

# Exact product and publisher checks; command strings and private paths never enter public JSON.
$valid = New-Registration -Uninstall $privateCommand
$wrongPublisher = New-Registration -Publisher 'Untrusted Publisher' -Scope currentUser
$installed = Get-UindosOneDrivePreflight -Providers (New-Providers -Machine64 @($valid) -Current64 @($wrongPublisher) -Running $true)
Assert-Test ($installed.installation.status -eq 'present' -and $installed.installation.matchingRegistrationCount -eq 1) 'Expected display-name and publisher metadata matched'
Assert-Test $installed.installation.identityReviewRequired 'Exact product name with unexpected publisher flagged'
Assert-Test ($installed.installation.registrations[0].uninstallCommandPresent -and $installed.installation.registrations[0].uninstallCommandSources -contains 'UninstallString') 'Only sanitized uninstall command metadata emitted'
Assert-Test ($installed.process.running -and $installed.process.status -eq 'running') 'Process presence reported as process presence'
Assert-Test ($installed.assessment.safeToUninstall -eq $false) 'No safe-to-uninstall claim'

# Configured account roots can establish KFM-like path placement; paths remain private.
$root = 'C:\Users\Private Person\OneDrive - Private Org'
$configured = Get-UindosOneDrivePreflight -Providers (New-Providers -Machine32 @((New-Registration -Scope machine32)) -Configured $true -Roots @($root) -Desktop "$root\Desktop" -Documents 'C:\Users\Private Person\Documents' -Pictures "$root\Pictures")
Assert-Test ($configured.currentUserAccount.registryMetadata -eq 'present' -and $configured.currentUserAccount.signInStatus -eq 'unknown') 'Account registry metadata is not reported as authenticated sign-in'
Assert-Test ($configured.knownFolders.desktop.redirectedToDetectedOneDriveRoot -eq $true) 'Desktop under detected root flagged'
Assert-Test ($configured.knownFolders.documents.redirectedToDetectedOneDriveRoot -eq $false) 'Documents outside detected root flagged false'
Assert-Test ($configured.knownFolders.pictures.redirectedToDetectedOneDriveRoot -eq $true) 'Pictures under detected root flagged'
$configuredWithoutRoot = Get-UindosOneDrivePreflight -Providers (New-Providers -Configured $true)
Assert-Test ($configuredWithoutRoot.currentUserAccount.registryMetadata -eq 'present' -and $configuredWithoutRoot.knownFolders.desktop.status -eq 'unknown') 'Account presence does not depend on root availability'
$missingKnownFolder = Get-UindosOneDrivePreflight -Providers (New-Providers -Configured $true -Roots @($root) -Desktop '')
Assert-Test ($missingKnownFolder.knownFolders.desktop.status -eq 'unknown' -and $null -eq $missingKnownFolder.knownFolders.desktop.redirectedToDetectedOneDriveRoot) 'Empty known-folder path remains unknown, not false'
Assert-Test ($null -eq (New-Registration -Name 'Contoso OneDrive Helper' -Publisher 'Contoso')) 'Substring product names are not matched'

# Partial access must not be converted into an absent install; provider errors are sanitized.
$partialProviders = New-Providers -Machine32Provider { throw [UnauthorizedAccessException]::new("Denied $privatePath") }
$partial = Get-UindosOneDrivePreflight -Providers $partialProviders
Assert-Test ($partial.installation.status -eq 'unknown' -and $partial.installation.registryCollection -eq 'partial') 'Partial registry inventory is unknown, not absent'
Assert-Test ($partial.probeStatus.machine32 -eq 'access-denied') 'Access denial distinguished'
$errorProviders = New-Providers -Machine64Provider { throw "failure $privatePath secret-token" }
$errorReport = Get-UindosOneDrivePreflight -Providers $errorProviders
$errorReports = [ordered]@{
    os = { $supportedOs }
    machine64 = { throw "failure $privatePath secret-token" }
    machine32 = { throw "failure $privatePath secret-token" }
    currentUser = { throw "failure $privatePath secret-token" }
    process = { [pscustomobject]@{ running=$false } }
    accounts = { [pscustomobject]@{ configured=$false; roots=@() } }
    knownFolders = { [pscustomobject]@{ desktop=''; documents=''; pictures='' } }
}
$failed = Get-UindosOneDrivePreflight -Providers $errorReports
Assert-Test ($errorReport.installation.status -eq 'unknown' -and $errorReport.probeStatus.machine64 -eq 'error') 'Partial provider error remains unknown and status is preserved'
Assert-Test ($failed.installation.status -eq 'error' -and $failed.installation.registryCollection -eq 'error') 'Total registry probe failure is distinct from unknown and absent'
$nullProviderReport = Get-UindosOneDrivePreflight -Providers (New-Providers -Machine64Provider { return $null })
Assert-Test ($nullProviderReport.installation.status -eq 'unknown' -and $nullProviderReport.probeStatus.machine64 -eq 'error') 'Malformed empty provider cannot become false absence'

$json = ConvertTo-Json -InputObject @($absent,$installed,$configured,$partial,$errorReport,$failed) -Depth 10 -Compress
foreach ($secret in @('Private Person','Private Org','OneDriveSetup.exe','secret-token','Untrusted Publisher','Contoso OneDrive Helper')) {
    Assert-Test (-not $json.Contains($secret)) "Public JSON excludes private or nonmatching registry data: $secret"
}
Assert-Test ($json.Contains('manual-review-required') -and $json.Contains('hydrationStatus')) 'Public report retains manual-review limits'

$unsupported = Get-UindosOneDrivePreflight -Providers ([ordered]@{
    os = { [pscustomobject]@{ editionId='Enterprise'; build='26300'; architecture='X64' } }
    machine64 = { [pscustomobject]@{ entries=[object[]]@() } }; machine32 = { [pscustomobject]@{ entries=[object[]]@() } }; currentUser = { [pscustomobject]@{ entries=[object[]]@() } }
    process = { [pscustomobject]@{ running=$false } }
    accounts = { [pscustomobject]@{ configured=$false; roots=@() } }
    knownFolders = { [pscustomobject]@{ desktop=''; documents=''; pictures='' } }
})
Assert-Test ($unsupported.platform.status -eq 'unsupported') 'Windows 11 Pro edition gate is reported'
Write-Output 'PASS: OneDrive preflight identity, privacy, unknown states, KFM signals, partial errors and platform gate'
