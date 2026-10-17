[CmdletBinding()]
param([Parameter()][string]$TestRoot)

# Portable PowerShell 7 mock-only tests. No Windows Registry or policy write is used.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\SharedExperiences.ps1')

function Assert-Test {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$supported = [pscustomobject]@{ editionId='Professional'; build='26300'; architecture='X64' }
$actions = @(Get-UindosSharedExperiencesActions -OsInfo $supported)
Assert-Test ($actions.Count -eq 1 -and $actions[0].id -eq 'shared-experiences.disable-continuation' -and
    $actions[0].path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -and
    $actions[0].name -eq 'EnableCdp' -and $actions[0].kind -eq 'DWord' -and
    $actions[0].value -eq 0) 'only machine EnableCDP participation policy is offered'
Assert-Test ((ConvertTo-UindosSharedExperiencesDword ([long]0)) -eq 0) 'Int64 journal prior DWORD normalizes for Undo'
$badDword=$false
try { [void](ConvertTo-UindosSharedExperiencesDword ([long]2147483648)) } catch [System.NotSupportedException] { $badDword=$true }
Assert-Test $badDword 'prior DWORD outside signed Int32 range fails closed'
$wrongKind=$false
try { Assert-UindosSharedExperiencesDwordKind -Kind 'String' } catch [System.NotSupportedException] { $wrongKind=$true }
Assert-Test $wrongKind 'existing non-DWORD policy fails closed'

foreach ($bad in @(
    [pscustomobject]@{editionId='Core';build='26300';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='22000';architecture='X86'},
    [pscustomobject]@{editionId='Enterprise';build='26300';architecture='Arm64'}
)) {
    $rejected=$false
    try { [void]@(Get-UindosSharedExperiencesActions -OsInfo $bad) } catch [System.NotSupportedException] { $rejected=$true }
    Assert-Test $rejected 'unsupported edition, build or architecture rejected'
}
Assert-Test (@(Get-UindosSharedExperiencesActions -OsInfo ([pscustomobject]@{editionId='ProfessionalN';build='22000';architecture='Arm64'})).Count -eq 1) 'minimum supported Pro N ARM64 build accepted'
Assert-Test (Test-UindosSharedExperiencesPolicyNameSignal -Names @('enablecdp') -Token 'EnableCDP') 'PolicyManager matching is case-insensitive for exact value names'
Assert-Test (Test-UindosSharedExperiencesPolicyNameSignal -Names @('EnableCDP_ProviderSet') -Token 'EnableCDP') 'PolicyManager matching accepts target metadata prefixes'
Assert-Test (-not (Test-UindosSharedExperiencesPolicyNameSignal -Names @('OtherEnableCDPSetting','EnableCDPExtra') -Token 'EnableCDP')) 'PolicyManager matching rejects substring and loose-prefix false positives'

$clearProbe = [pscustomobject]@{
    domainJoined=$false; localMachineRegistryPol='absent'
    policyManagerEnableCDP='absent'; policyManagerAllowConnectedDevices='absent'
    enrollmentArtifactRoots=33; providerArtifactRoots=6
}
$clearAuthority = Get-UindosSharedExperiencesAuthority -Probe $clearProbe
Assert-Test ($clearAuthority.classification -eq 'clear' -and $clearAuthority.signals.enrollmentArtifacts -eq 'present') 'enrollment/provider roots are informational and do not imply active management'
$blockedAuthority = Get-UindosSharedExperiencesAuthority -Probe ([pscustomobject]@{
    domainJoined=$true; localMachineRegistryPol='absent'
    policyManagerEnableCDP='absent'; policyManagerAllowConnectedDevices='absent'
    enrollmentArtifactRoots=0; providerArtifactRoots=0
})
Assert-Test ($blockedAuthority.classification -eq 'blocked') 'domain-joined authority blocks Apply'
$localPolicyAuthority = Get-UindosSharedExperiencesAuthority -Probe ([pscustomobject]@{
    domainJoined=$false; localMachineRegistryPol='present-unparsed'
    policyManagerEnableCDP='absent'; policyManagerAllowConnectedDevices='absent'
    enrollmentArtifactRoots=0; providerArtifactRoots=0
})
Assert-Test ($localPolicyAuthority.classification -eq 'blocked') 'local Registry.pol presence blocks Apply without parsing/overwriting it'
$mdmAuthority = Get-UindosSharedExperiencesAuthority -Probe ([pscustomobject]@{
    domainJoined=$false; localMachineRegistryPol='absent'
    policyManagerEnableCDP='present'; policyManagerAllowConnectedDevices='absent'
    enrollmentArtifactRoots=1; providerArtifactRoots=1
})
Assert-Test ($mdmAuthority.classification -eq 'blocked') 'PolicyManager EnableCDP signal blocks Apply'
$connectedDevicesAuthority = Get-UindosSharedExperiencesAuthority -Probe ([pscustomobject]@{
    domainJoined=$false; localMachineRegistryPol='absent'
    policyManagerEnableCDP='absent'; policyManagerAllowConnectedDevices='present'
    enrollmentArtifactRoots=0; providerArtifactRoots=0
})
Assert-Test ($connectedDevicesAuthority.classification -eq 'blocked') 'PolicyManager AllowConnectedDevices signal blocks Apply'
$unknownAuthority = Get-UindosSharedExperiencesAuthority -Probe ([pscustomobject]@{
    domainJoined=$false; localMachineRegistryPol='absent'
    policyManagerEnableCDP='absent'; policyManagerAllowConnectedDevices='unknown'
    enrollmentArtifactRoots=$null; providerArtifactRoots=$null
})
Assert-Test ($unknownAuthority.classification -eq 'unknown' -and $unknownAuthority.signals.enrollmentArtifacts -eq 'unreadable') 'unreadable authority probe fails closed and reports sanitized status'
$invalidDomainAuthority = Get-UindosSharedExperiencesAuthority -Probe ([pscustomobject]@{
    domainJoined='false'; localMachineRegistryPol='absent'
    policyManagerEnableCDP='absent'; policyManagerAllowConnectedDevices='absent'
    enrollmentArtifactRoots=0; providerArtifactRoots=0
})
Assert-Test ($invalidDomainAuthority.classification -eq 'unknown') 'domain-join probe accepts only an actual Boolean and fails closed on strings'

$testRoot = if ([string]::IsNullOrWhiteSpace($TestRoot)) { [IO.Path]::GetTempPath() } else { $TestRoot }
if (-not [IO.Path]::IsPathFullyQualified($testRoot)) { throw 'TestRoot must be an absolute path.' }
$null = [IO.Directory]::CreateDirectory($testRoot)
$dir = Join-Path $testRoot ('shared-experiences-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($dir)
$script:state = @{}
$script:writes = 0
$script:denyWrite = $false
$key = "$($actions[0].path)|$($actions[0].name)"
$mock = @{
    ValidateAction = { param($Action) Assert-UindosSharedExperiencesAction -Action $Action }
    Read = {
        param($Path,$Name)
        Assert-UindosSharedExperiencesTarget -Path $Path -Name $Name
        $target = "$Path|$Name"
        if ($script:state.ContainsKey($target)) { return $script:state[$target] }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write = {
        param($Path,$Name,$Kind,$Value)
        Assert-UindosSharedExperiencesTarget -Path $Path -Name $Name
        if ($script:denyWrite) { throw [System.UnauthorizedAccessException]::new('mock denied') }
        if ($Kind -cne 'DWord') { throw 'unexpected mock write type' }
        $safe = ConvertTo-UindosSharedExperiencesDword $Value
        $script:state["$Path|$Name"] = [pscustomobject]@{exists=$true;kind='DWord';value=$safe}
        $script:writes++
    }
    Remove = {
        param($Path,$Name)
        Assert-UindosSharedExperiencesTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:writes++
    }
}

try {
    # Preview is independent of LOCALAPPDATA and does not create a journal.
    $plan=Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 1 -and $script:writes -eq 0 -and [IO.Directory]::GetFiles($dir).Count -eq 0) 'read-only preview makes no journal or policy change'
    $authorityPlan = [pscustomobject]@{plan=$plan;authority=$clearAuthority}
    Assert-Test ($authorityPlan.authority.classification -eq 'clear' -and $authorityPlan.plan.changeCount -eq 1) 'preview can report sanitized authority classification with the plan'

    foreach ($denial in @($blockedAuthority,$unknownAuthority)) {
        $blockedJournal = Join-Path $dir ('blocked-' + [guid]::NewGuid().ToString('N'))
        $blocked=$false
        try { [void](Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $blockedJournal -Authority $denial) } catch { $blocked=$true }
        Assert-Test ($blocked -and $script:writes -eq 0 -and -not [IO.Directory]::Exists($blockedJournal)) 'blocked/unknown authority creates no journal and performs no writes'
    }
    $notConfirmed=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) } catch { $notConfirmed=$true }
    Assert-Test ($notConfirmed -and $script:writes -eq 0) 'transaction engine still requires explicit Apply confirmation'

    $applied=Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $dir -Authority $clearAuthority
    Assert-Test ($applied.status -eq 'applied' -and $script:state[$key].value -eq 0) 'authorized Apply writes exact DWORD 0'
    Assert-Test ((Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $dir -Authority $clearAuthority).status -eq 'unchanged') 'repeat Apply is idempotent'
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and -not $script:state.ContainsKey($key)) 'Undo restores prior absence'

    $script:state[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=1}
    $applied=Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $dir -Authority $clearAuthority
    $journal=Get-Content -LiteralPath (Join-Path $dir ($applied.transactionId + '.json')) -Raw | ConvertFrom-Json -Depth 20
    Assert-Test ($journal.steps[0].prior.value -is [long]) 'journal reload uses Int64 for prior DWORD'
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state[$key].value -eq 1) 'Undo restores an existing DWORD prior state'

    # A newly observed authority conflict does not block journal-based Undo.
    $applied=Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $dir -Authority $clearAuthority
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone') 'Undo recovery is independent of current authority signals'

    $script:denyWrite=$true
    $failed=$false
    try { [void](Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $dir -Authority $clearAuthority) } catch { $failed=$true }
    Assert-Test ($failed -and $script:state[$key].value -eq 1) 'denied registry write raises failure and preserves prior value'
    $script:denyWrite=$false

    $applied=Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $mock -JournalDirectory $dir -Authority $clearAuthority
    $script:state[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=2}
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'needs-review' -and $script:state[$key].value -eq 2) 'Undo preserves drift and reports conflict'

    foreach ($mutant in @(
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='DWord';value=1},
        [pscustomobject]@{id=$actions[0].id;path='HKCU:\SOFTWARE\Policies\Microsoft\Windows\System';name=$actions[0].name;kind='DWord';value=0},
        [pscustomobject]@{id='shared-experiences.other';path=$actions[0].path;name=$actions[0].name;kind='DWord';value=0},
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name='EnableMMX';kind='DWord';value=0},
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='String';value=0}
    )) {
        $rejected=$false
        try { [void](Get-UindosPlan -Actions @($mutant) -Adapter $mock) } catch { $rejected=$true }
        Assert-Test $rejected 'action allowlist rejects value, path, identity, name or kind changes'
    }
    foreach ($target in @(
        [pscustomobject]@{path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\System';name='EnableMMX'},
        [pscustomobject]@{path='HKCU:\SOFTWARE\Policies\Microsoft\Windows\System';name='EnableCdp'},
        [pscustomobject]@{path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\ConnectedDevicesPlatform';name='AllowConnectedDevices'}
    )) {
        $rejected=$false
        try { Assert-UindosSharedExperiencesTarget -Path $target.path -Name $target.name } catch [System.NotSupportedException] { $rejected=$true }
        Assert-Test $rejected 'adapter target guard rejects other policies and hives'
    }

    $defaultJournal=Get-UindosSharedExperiencesJournalDirectory -HasOverride:$false -LocalAppData (Join-Path $TestRoot 'mock-localappdata')
    Assert-Test ($defaultJournal -eq (Join-Path (Join-Path $TestRoot 'mock-localappdata') 'uindos\transactions\shared-experiences-v1')) 'default journal path is versioned under LocalAppData'
    $missingLocalAppData=$false
    try { [void](Get-UindosSharedExperiencesJournalDirectory -HasOverride:$false -LocalAppData '') } catch { $missingLocalAppData=$true }
    Assert-Test $missingLocalAppData 'default journal path fails closed without LOCALAPPDATA'
    Assert-Test ((Get-UindosSharedExperiencesJournalDirectory -JournalDirectory $dir -HasOverride:$true -LocalAppData '') -eq [IO.Path]::GetFullPath($dir)) 'absolute journal override works without LOCALAPPDATA'
    foreach ($invalidPath in @('relative\journal','')) {
        $rejected=$false
        try { [void](Get-UindosSharedExperiencesJournalDirectory -JournalDirectory $invalidPath -HasOverride:$true -LocalAppData 'C:\Users\Test') } catch { $rejected=$true }
        Assert-Test $rejected 'relative or blank journal override rejected'
    }
    $filePath=Join-Path $dir 'not-a-directory'
    [IO.File]::WriteAllText($filePath,'fixture')
    $rejectedFile=$false
    try { [void](Get-UindosSharedExperiencesJournalDirectory -JournalDirectory $filePath -HasOverride:$true -LocalAppData '') } catch { $rejectedFile=$true }
    Assert-Test $rejectedFile 'journal override that names a file is rejected'

    $notAdmin=$false
    try { Assert-UindosSharedExperiencesWriteAuthorization -IsAdministrator $false } catch { $notAdmin=$true }
    Assert-Test $notAdmin 'Apply and Undo require an already elevated process'
    Write-Output 'PASS: EnableCDP allowlist, platform gate, authority guard, preview, Apply/repeat/Undo, prior DWORD, failure, drift and journal guards'
}
finally {
    # The transaction engine creates only flat JSON/.lock files here. Remove
    # those explicitly and delete only this unique test directory nonrecursively.
    if ([IO.Directory]::Exists($dir)) {
        foreach ($file in [IO.Directory]::GetFiles($dir)) { [IO.File]::Delete($file) }
        [IO.Directory]::Delete($dir)
    }
}
