# Cross-platform transaction and guard checks for the fixed Start reset module.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\StartReset.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Assert-Throws { param([scriptblock]$Operation,[string]$Message) $failed=$false; try { & $Operation } catch { $failed=$true }; Assert-Test $failed $Message }

$catalog = @(Get-UindosStartResetCatalog)
Assert-Test ($catalog.Count -eq 2) 'Exactly two fixed policy actions'
Assert-Test ($catalog[0].id -ceq 'start.configure-pins-json' -and $catalog[0].path -ceq 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -and
    $catalog[0].name -ceq 'ConfigureStartPinsJSON' -and $catalog[0].kind -ceq 'ExpandString' -and
    $catalog[0].value -ceq '{"applyOnce":true,"pinnedList":[]}') 'Exact raw JSON action is first'
Assert-Test ($catalog[1].id -ceq 'start.enable-pins-policy' -and $catalog[1].name -ceq 'ConfigureStartPins' -and
    $catalog[1].kind -ceq 'DWord' -and $catalog[1].value -is [int] -and $catalog[1].value -eq 1) 'Enable action is second'

$supported = [pscustomobject]@{editionId='Professional';build='26300';ubr='9711';architecture='X64'}
Assert-Test (@(Get-UindosStartResetActions -OsInfo $supported).Count -eq 2) 'Validated Pro build accepted'
Assert-Test (@(Get-UindosStartResetActions -OsInfo ([pscustomobject]@{editionId='ProfessionalN';build='26300';ubr='9712';architecture='Arm64'})).Count -eq 2) 'Validated Pro N ARM64 accepted'
foreach ($unsupported in @(
    [pscustomobject]@{editionId='Core';build='26300';ubr='9711';architecture='X64'},
    [pscustomobject]@{editionId='Enterprise';build='26300';ubr='9711';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='26300';ubr='9711';architecture='X86'},
    [pscustomobject]@{editionId='Professional';build='26300';ubr='9710';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='26301';ubr='9711';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='26300';ubr='9711';architecture='X64';preview=$true},
    [pscustomobject]@{editionId='Professional';build='26300';architecture='X64'}
)) { Assert-Throws { Get-UindosStartResetActions -OsInfo $unsupported } 'Unsupported or incomplete OS gate rejected' }

$script:state = @{}
$script:writes = [System.Collections.Generic.List[object]]::new()
$script:removes = [System.Collections.Generic.List[string]]::new()
$mock = @{
    ValidateAction = { param($Action) Assert-UindosStartResetAction -Action $Action }
    Read = {
        param($Path,$Name)
        Assert-UindosStartResetTarget -Path $Path -Name $Name
        $key = "$Path|$Name"
        if (-not $script:state.ContainsKey($key)) { return [pscustomobject]@{exists=$false;kind=$null;value=$null} }
        $current = $script:state[$key]
        $expected = if ($Name -ceq 'ConfigureStartPinsJSON') { 'ExpandString' } else { 'DWord' }
        if ($current.kind -cne $expected) { throw 'Existing value has wrong kind.' }
        if ($expected -ceq 'ExpandString' -and $current.value -isnot [string]) { throw 'Existing ExpandString is malformed.' }
        if ($expected -ceq 'DWord' -and $current.value -isnot [int]) { throw 'Existing DWORD is malformed.' }
        return $current
    }
    Write = {
        param($Path,$Name,$Kind,$Value)
        Assert-UindosStartResetTarget -Path $Path -Name $Name
        $expected = if ($Name -ceq 'ConfigureStartPinsJSON') { 'ExpandString' } else { 'DWord' }
        if ($Kind -cne $expected) { throw 'Mock received unexpected registry kind.' }
        if ($expected -ceq 'ExpandString') {
            if ($Value -isnot [string]) { throw 'Mock requires actual string data.' }
            $safe = $Value
        } else { $safe = ConvertTo-UindosStartResetDword -Value $Value }
        $script:state["$Path|$Name"] = [pscustomobject]@{exists=$true;kind=$Kind;value=$safe}
        $script:writes.Add([pscustomobject]@{path=$Path;name=$Name;kind=$Kind;value=$safe})
    }
    Remove = {
        param($Path,$Name)
        Assert-UindosStartResetTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:removes.Add($Name)
    }
}

$jsonKey = "$($catalog[0].path)|$($catalog[0].name)"
$flagKey = "$($catalog[1].path)|$($catalog[1].name)"
$mockDir = Join-Path ([IO.Path]::GetTempPath()) ('uindos-start-reset-mock-' + [Guid]::NewGuid().ToString('D'))
try {
    $plan = Get-UindosPlan -Actions @(Get-UindosStartResetActions -OsInfo $supported) -Adapter $mock
    Assert-Test ($plan.mode -eq 'read-only' -and $plan.changeCount -eq 2 -and $script:writes.Count -eq 0 -and -not (Test-Path -LiteralPath $mockDir)) 'Preview is read-only and reports both absent policies'
    Assert-Throws { Invoke-UindosApply -Actions $catalog -Adapter $mock -JournalDirectory $mockDir } 'Apply confirmation required'
    $applied = Invoke-UindosApply -Actions $catalog -Adapter $mock -JournalDirectory $mockDir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $applied.changeCount -eq 2) 'Apply writes both fixed values'
    Assert-Test ($script:state[$jsonKey].kind -ceq 'ExpandString' -and $script:state[$jsonKey].value -ceq $catalog[0].value -and
        $script:state[$flagKey].kind -ceq 'DWord' -and $script:state[$flagKey].value -is [int] -and $script:state[$flagKey].value -eq 1) 'Desired raw pair verified'
    $repeat = Invoke-UindosApply -Actions $catalog -Adapter $mock -JournalDirectory $mockDir -ConfirmChanges
    Assert-Test ($repeat.status -eq 'unchanged' -and $script:writes.Count -eq 2) 'Repeat Apply is unchanged'
    $undo = Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $mockDir
    Assert-Test ($undo.status -eq 'undone' -and $script:state.Count -eq 0 -and $script:removes.Count -eq 2) 'Undo of initially absent policy removes only the two exact values'

    # ExpandString prior data remains literal across journal serialization and Undo.
    $priorJson = '%UINDOS_TEST_ROOT%\\pins\\雪"keep"'
    $script:state[$jsonKey] = [pscustomobject]@{exists=$true;kind='ExpandString';value=$priorJson}
    $script:state[$flagKey] = [pscustomobject]@{exists=$true;kind='DWord';value=[int]-7}
    $priorTx = Invoke-UindosApply -Actions $catalog -Adapter $mock -JournalDirectory $mockDir -ConfirmChanges
    $journal = Get-Content -LiteralPath (Join-Path $mockDir "$($priorTx.transactionId).json") -Raw | ConvertFrom-Json -Depth 20
    Assert-Test ($journal.steps[0].prior.kind -ceq 'ExpandString' -and $journal.steps[0].prior.value -ceq $priorJson) 'Journal preserves raw prior expandable string'
    Assert-Test ($journal.steps[1].prior.value -eq -7) 'Journal preserves signed prior DWORD'
    $restore = Invoke-UindosUndo -TransactionId $priorTx.transactionId -Adapter $mock -JournalDirectory $mockDir
    Assert-Test ($restore.status -eq 'undone' -and $script:state[$jsonKey].kind -ceq 'ExpandString' -and
        $script:state[$jsonKey].value -ceq $priorJson -and $script:state[$flagKey].kind -ceq 'DWord' -and
        $script:state[$flagKey].value -is [int] -and $script:state[$flagKey].value -eq -7) 'Undo restores exact prior raw data and signed DWORD'

    foreach ($case in @(
        @{key=$jsonKey;state=[pscustomobject]@{exists=$true;kind='String';value=$catalog[0].value}},
        @{key=$flagKey;state=[pscustomobject]@{exists=$true;kind='QWord';value=[long]1}},
        @{key=$jsonKey;state=[pscustomobject]@{exists=$true;kind='ExpandString';value=1}},
        @{key=$flagKey;state=[pscustomobject]@{exists=$true;kind='DWord';value='1'}}
    )) {
        $script:state.Clear(); $script:state[$case.key]=$case.state
        Assert-Throws { Get-UindosPlan -Actions $catalog -Adapter $mock } 'Malformed or wrong prior kind rejected'
    }
    $script:state.Clear()
    foreach ($mutant in @(
        [pscustomobject]@{id=$catalog[0].id;path=$catalog[0].path;name=$catalog[0].name;kind='String';value=$catalog[0].value},
        [pscustomobject]@{id=$catalog[0].id;path='HKLM:\Software\Policies\Microsoft\Windows\Explorer';name=$catalog[0].name;kind='ExpandString';value=$catalog[0].value},
        [pscustomobject]@{id=$catalog[1].id;path=$catalog[1].path;name=$catalog[1].name;kind='DWord';value=0},
        [pscustomobject]@{id=$catalog[1].id;path=$catalog[1].path;name='LockedStartLayout';kind='DWord';value=1}
    )) { Assert-Throws { Get-UindosPlan -Actions @($mutant) -Adapter $mock } 'Mutated action rejected' }
    Assert-Throws { & $mock.Remove $catalog[0].path 'LockedStartLayout' } 'Remove cannot target another policy value'
    Assert-Throws { ConvertTo-UindosStartResetDword ([long]2147483648) } 'Out-of-range DWORD rejected'
    Assert-Throws { ConvertTo-UindosStartResetDword '1' } 'String DWORD coercion rejected'
    $driftTx = Invoke-UindosApply -Actions $catalog -Adapter $mock -JournalDirectory $mockDir -ConfirmChanges
    $script:state[$jsonKey]=[pscustomobject]@{exists=$true;kind='ExpandString';value='drift'}
    $driftUndo = Invoke-UindosUndo -TransactionId $driftTx.transactionId -Adapter $mock -JournalDirectory $mockDir
    Assert-Test ($driftUndo.status -eq 'needs-review' -and $script:state[$jsonKey].value -ceq 'drift') 'Undo detects and preserves JSON policy drift'

    $clean = [pscustomobject]@{
        domainJoined=$false; cloudJoinPresent=$false; mdmAccountsPresent=$false; userGpoPresent=$false
        machineGpoPresent=$false; probeComplete=$true; hkcuLayoutPolicyPresent=$false
        hkcuOtherLayoutPolicyPresent=$false; hklmLayoutPolicyPresent=$false; mdmStartPolicyPresent=$false
    }
    Assert-Test ((Test-UindosStartResetGuard -Observations $clean).allowed) 'Complete unmanaged observation set is allowed'
    foreach ($field in @('domainJoined','cloudJoinPresent','mdmAccountsPresent','userGpoPresent','machineGpoPresent','hklmLayoutPolicyPresent','mdmStartPolicyPresent')) {
        $flagged = $clean.PSObject.Copy(); $flagged.$field = $true
        Assert-Test (-not (Test-UindosStartResetGuard -Observations $flagged).allowed) "Guard blocks $field"
    }
    $owned = $clean.PSObject.Copy(); $owned.hkcuLayoutPolicyPresent = $true
    Assert-Test (-not (Test-UindosStartResetGuard -Observations $owned).allowed) 'Existing HKCU policy blocks by default'
    Assert-Test ((Test-UindosStartResetGuard -Observations $owned -AllowOwnedPolicy).allowed) 'Only owned HKCU policy can be explicitly allowed after caller validation'
    $otherOwned = $clean.PSObject.Copy(); $otherOwned.hkcuOtherLayoutPolicyPresent = $true
    Assert-Test (-not (Test-UindosStartResetGuard -Observations $otherOwned -AllowOwnedPolicy).allowed) 'Owned pair exception never bypasses other HKCU layout policies'
    foreach ($field in @('domainJoined','cloudJoinPresent','mdmAccountsPresent','userGpoPresent','machineGpoPresent','probeComplete','hkcuLayoutPolicyPresent','hkcuOtherLayoutPolicyPresent','hklmLayoutPolicyPresent','mdmStartPolicyPresent')) {
        $unknown = $clean.PSObject.Copy(); $unknown.$field = $null
        Assert-Test (-not (Test-UindosStartResetGuard -Observations $unknown -AllowOwnedPolicy).allowed) "Guard blocks unknown $field"
        $wrongType = $clean.PSObject.Copy(); $wrongType.$field = 'false'
        Assert-Test (-not (Test-UindosStartResetGuard -Observations $wrongType -AllowOwnedPolicy).allowed) "Guard blocks nonboolean $field"
    }
    $incomplete = $clean.PSObject.Copy(); $incomplete.probeComplete = $false
    Assert-Test (-not (Test-UindosStartResetGuard -Observations $incomplete).allowed) 'Incomplete probe blocks even when flags are false'
    Assert-Throws { Get-UindosPlan -Actions @($catalog[0],$catalog[0]) -Adapter $mock } 'Duplicate fixed target rejected by engine'

    Write-Output 'PASS: Start reset fixed catalog/OS gate, exact Apply/repeat/Undo, raw ExpandString and signed DWORD journal roundtrip, drift/type/action rejection, and management guard'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath($mockDir)
    $leaf = [IO.Path]::GetFileName($resolved)
    $validLeaf = $leaf -match '^uindos-start-reset-mock-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if ($validLeaf -and $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
