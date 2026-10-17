[CmdletBinding()]
param([Parameter()][string]$TestRoot)

# Portable PowerShell 7 mock-only tests. No Windows Registry or policy write is used.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\OneDrivePolicy.ps1')

function Assert-Test {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$supported = [pscustomobject]@{ editionId='Professional'; build='26300'; architecture='X64' }
$actions = @(Get-UindosOneDrivePolicyActions -OsInfo $supported)
Assert-Test ($actions.Count -eq 1 -and $actions[0].id -eq 'onedrive.disable-file-sync' -and
    $actions[0].path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' -and
    $actions[0].name -eq 'DisableFileSyncNGSC' -and $actions[0].kind -eq 'DWord' -and
    $actions[0].value -eq 1) 'only the supported machine file-sync policy is offered'
Assert-Test ((ConvertTo-UindosOneDrivePolicyDword ([long]0)) -eq 0) 'Int64 JSON journal prior DWORD normalizes for Undo'
$badDword=$false
try { [void](ConvertTo-UindosOneDrivePolicyDword ([long]2147483648)) } catch [System.NotSupportedException] { $badDword=$true }
Assert-Test $badDword 'prior DWORD values outside signed Int32 range fail closed'
$wrongKind=$false
try { Assert-UindosOneDrivePolicyDwordKind -Kind 'String' } catch [System.NotSupportedException] { $wrongKind=$true }
Assert-Test $wrongKind 'existing non-DWORD policy fails closed'

foreach ($bad in @(
    [pscustomobject]@{editionId='Core';build='26300';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='22000';architecture='X86'},
    [pscustomobject]@{editionId='Enterprise';build='26300';architecture='Arm64'}
)) {
    $rejected=$false
    try { [void]@(Get-UindosOneDrivePolicyActions -OsInfo $bad) } catch [System.NotSupportedException] { $rejected=$true }
    Assert-Test $rejected 'unsupported edition, build or architecture rejected'
}
Assert-Test (@(Get-UindosOneDrivePolicyActions -OsInfo ([pscustomobject]@{editionId='ProfessionalN';build='22000';architecture='Arm64'})).Count -eq 1) 'minimum supported Pro N ARM64 build accepted'

$testRoot = if ([string]::IsNullOrWhiteSpace($TestRoot)) { [IO.Path]::GetTempPath() } else { $TestRoot }
if (-not [IO.Path]::IsPathFullyQualified($testRoot)) { throw 'TestRoot must be an absolute path.' }
$null = [IO.Directory]::CreateDirectory($testRoot)
$dir = Join-Path $testRoot ('onedrive-policy-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($dir)
$script:state = @{}
$script:writes = 0
$script:denyWrite = $false
$key = "$($actions[0].path)|$($actions[0].name)"
$mock = @{
    ValidateAction = { param($Action) Assert-UindosOneDrivePolicyAction -Action $Action }
    Read = {
        param($Path,$Name)
        Assert-UindosOneDrivePolicyTarget -Path $Path -Name $Name
        $target = "$Path|$Name"
        if ($script:state.ContainsKey($target)) { return $script:state[$target] }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write = {
        param($Path,$Name,$Kind,$Value)
        Assert-UindosOneDrivePolicyTarget -Path $Path -Name $Name
        if ($script:denyWrite) { throw [System.UnauthorizedAccessException]::new('mock denied') }
        if ($Kind -cne 'DWord') { throw 'unexpected mock write type' }
        $safe = ConvertTo-UindosOneDrivePolicyDword $Value
        $script:state["$Path|$Name"] = [pscustomobject]@{exists=$true;kind='DWord';value=$safe}
        $script:writes++
    }
    Remove = {
        param($Path,$Name)
        Assert-UindosOneDrivePolicyTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:writes++
    }
}

try {
    # Plan does not resolve LOCALAPPDATA or create/read a journal directory.
    $plan=Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 1 -and $script:writes -eq 0 -and [IO.Directory]::GetFiles($dir).Count -eq 0) 'read-only preview makes no journal or policy change'
    $blocked=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) } catch { $blocked=$true }
    Assert-Test ($blocked -and $script:writes -eq 0) 'engine requires explicit Apply confirmation'

    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $script:state[$key].value -eq 1) 'policy Apply writes exact DWORD 1'
    Assert-Test ((Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges).status -eq 'unchanged') 'repeat Apply is idempotent'
    # No OneDrive installation/provider is involved in Undo; journal + allowlisted adapter suffice.
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and -not $script:state.ContainsKey($key)) 'Undo restores prior absence without requiring OneDrive installed'

    $script:state[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=0}
    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $journalPath=Join-Path $dir ($applied.transactionId + '.json')
    $journal=Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -Depth 20
    Assert-Test ($journal.steps[0].prior.value -is [long]) 'mock journal serializes prior DWORD as integer for reload coverage'
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state[$key].value -eq 0) 'Undo restores an existing DWORD prior state'

    $script:denyWrite=$true
    $failed=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges) } catch { $failed=$true }
    Assert-Test ($failed -and $script:state[$key].value -eq 0) 'denied write raises failure and preserves prior value'
    $script:denyWrite=$false

    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $script:state[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=2}
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'needs-review' -and $script:state[$key].value -eq 2) 'Undo preserves drift and reports conflict'

    foreach ($mutant in @(
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='DWord';value=0},
        [pscustomobject]@{id=$actions[0].id;path='HKCU:\Software\Microsoft\OneDrive';name=$actions[0].name;kind='DWord';value=1},
        [pscustomobject]@{id='onedrive.other';path=$actions[0].path;name=$actions[0].name;kind='DWord';value=1},
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name='DisableFileSync';kind='DWord';value=1},
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name='DisableFileSyncNGSC';kind='String';value=1}
    )) {
        $rejected=$false
        try { [void](Get-UindosPlan -Actions @($mutant) -Adapter $mock) } catch { $rejected=$true }
        Assert-Test $rejected 'action allowlist rejects value, path, identity, name or kind changes'
    }
    foreach ($target in @(
        [pscustomobject]@{path='HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive';name='DisableFileSync'},
        [pscustomobject]@{path='HKCU:\SOFTWARE\Policies\Microsoft\Windows\OneDrive';name='DisableFileSyncNGSC'}
    )) {
        $rejected=$false
        try { Assert-UindosOneDrivePolicyTarget -Path $target.path -Name $target.name } catch [System.NotSupportedException] { $rejected=$true }
        Assert-Test $rejected 'adapter target guard rejects other policy names and hives'
    }

    $mockLocalAppData=Join-Path $TestRoot 'mock-localappdata'
    $defaultJournal=Get-UindosOneDrivePolicyJournalDirectory -HasOverride:$false -LocalAppData $mockLocalAppData
    Assert-Test ($defaultJournal -eq (Join-Path $mockLocalAppData 'uindos\transactions\onedrive-policy-v1')) 'default journal path is versioned under LocalAppData'
    $missingLocalAppData=$false
    try { [void](Get-UindosOneDrivePolicyJournalDirectory -HasOverride:$false -LocalAppData '') } catch { $missingLocalAppData=$true }
    Assert-Test $missingLocalAppData 'write journal fails closed without LOCALAPPDATA when no override is supplied'
    Assert-Test ((Get-UindosOneDrivePolicyJournalDirectory -JournalDirectory $dir -HasOverride:$true -LocalAppData '') -eq [IO.Path]::GetFullPath($dir)) 'absolute private journal override works without LOCALAPPDATA'
    foreach ($invalidPath in @('relative\journal','')) {
        $rejected=$false
        try { [void](Get-UindosOneDrivePolicyJournalDirectory -JournalDirectory $invalidPath -HasOverride:$true -LocalAppData 'C:\Users\Test') } catch { $rejected=$true }
        Assert-Test $rejected 'relative or blank journal override rejected'
    }
    $filePath=Join-Path $dir 'not-a-directory'
    [IO.File]::WriteAllText($filePath,'fixture')
    $rejectedFile=$false
    try { [void](Get-UindosOneDrivePolicyJournalDirectory -JournalDirectory $filePath -HasOverride:$true -LocalAppData '') } catch { $rejectedFile=$true }
    Assert-Test $rejectedFile 'journal override that names a file is rejected'

    $notAdmin=$false
    try { Assert-UindosOneDrivePolicyWriteAuthorization -IsAdministrator $false } catch { $notAdmin=$true }
    Assert-Test $notAdmin 'Apply and Undo authorization guard requires an already elevated process'
    Write-Output 'PASS: OneDrive file-sync policy allowlist, platform gate, read-only plan, Apply/repeat/Undo, prior DWORD, failure, drift and journal guards'
}
finally {
    # Core creates only flat JSON/.lock files in this unique directory. Remove
    # those files explicitly; never recurse through a supplied TestRoot.
    if ([IO.Directory]::Exists($dir)) {
        foreach ($file in [IO.Directory]::GetFiles($dir)) { [IO.File]::Delete($file) }
        [IO.Directory]::Delete($dir)
    }
}
