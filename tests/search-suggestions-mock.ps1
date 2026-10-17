# Cross-platform mock-only test for the fixed Search suggestions policy.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\SearchSuggestions.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Assert-Throws {
    param([scriptblock]$Operation, [string]$Message)
    $failed = $false
    try { & $Operation } catch { $failed = $true }
    Assert-Test $failed $Message
}

$fakeOs = [pscustomobject]@{ editionId='Professional'; build='26100'; architecture='X64' }
$actions = @(Get-UindosSearchSuggestionsActions -OsInfo $fakeOs)
$rule = (Get-UindosSearchSuggestionsCatalog)[0]
Assert-Test ($actions.Count -eq 1 -and $actions[0].id -ceq 'search.disable-box-suggestions') 'One fixed action'
Assert-Test ($actions[0].path -ceq 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -and
    $actions[0].name -ceq 'DisableSearchBoxSuggestions' -and $actions[0].kind -ceq 'DWord' -and
    $actions[0].value -is [int] -and $actions[0].value -eq 1) 'Exact policy target and desired DWORD'

foreach ($unsupported in @(
    [pscustomobject]@{editionId='Core';build='26100';architecture='X64'},
    [pscustomobject]@{editionId='Enterprise';build='26100';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='26100';architecture='X86'},
    [pscustomobject]@{editionId='ProfessionalN';build='21999';architecture='Arm64'}
)) { Assert-Throws { Get-UindosSearchSuggestionsActions -OsInfo $unsupported } 'Unsupported OS rejected' }
Assert-Test (@(Get-UindosSearchSuggestionsActions -OsInfo ([pscustomobject]@{editionId='ProfessionalN';build='22000';architecture='Arm64'})).Count -eq 1) 'Pro N ARM64 supported at minimum build'

$script:state = @{}
$script:writes = 0
$script:removes = 0
$adapter = @{
    ValidateAction = { param($Action) Assert-UindosSearchSuggestionsAction -Action $Action }
    Read = {
        param($Path,$Name)
        Assert-UindosSearchSuggestionsTarget -Path $Path -Name $Name
        $key = "$Path|$Name"
        if (-not $script:state.ContainsKey($key)) { return [pscustomobject]@{exists=$false;kind=$null;value=$null} }
        $current = $script:state[$key]
        if ($current.kind -cne 'DWord') { throw 'Existing search value is not DWORD.' }
        return $current
    }
    Write = {
        param($Path,$Name,$Kind,$Value)
        Assert-UindosSearchSuggestionsTarget -Path $Path -Name $Name
        if ($Kind -cne 'DWord') { throw 'Mock only accepts DWORD.' }
        $safe = ConvertTo-UindosSearchSuggestionsDword -Value $Value
        $script:state["$Path|$Name"] = [pscustomobject]@{exists=$true;kind='DWord';value=$safe}
        $script:writes++
    }
    Remove = {
        param($Path,$Name)
        Assert-UindosSearchSuggestionsTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:removes++
    }
}

$dir = Join-Path ([IO.Path]::GetTempPath()) ('uindos-search-suggestions-mock-' + [Guid]::NewGuid().ToString('N'))
try {
    $plan = Get-UindosPlan -Actions $actions -Adapter $adapter
    Assert-Test ($plan.mode -eq 'read-only' -and $plan.changeCount -eq 1) 'Dry-run reports one pending change'
    Assert-Test ($script:writes -eq 0 -and -not (Test-Path -LiteralPath $dir)) 'Dry-run creates no journal or registry changes'
    Assert-Throws { Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir } 'Apply requires explicit confirmation'
    Assert-Test ($script:writes -eq 0) 'Unconfirmed apply has no writes'

    $applied = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $script:writes -eq 1) 'Explicit apply writes once'
    $same = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($same.status -eq 'unchanged' -and $script:writes -eq 1) 'Repeat apply is unchanged'
    $undo = Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state.Count -eq 0) 'Undo restores absence'

    foreach ($prior in @(0,7,-1,[int]::MinValue,[int]::MaxValue)) {
        $key = "$($rule.path)|$($rule.name)"
        $script:state[$key] = [pscustomobject]@{exists=$true;kind='DWord';value=[int]$prior}
        $tx = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
        $journal = Get-Content -LiteralPath (Join-Path $dir "$($tx.transactionId).json") -Raw | ConvertFrom-Json -Depth 20
        Assert-Test ($journal.steps[0].prior.value -is [long] -and $journal.steps[0].prior.value -eq $prior) "Journal records prior DWORD $prior"
        $restored = Invoke-UindosUndo -TransactionId $tx.transactionId -Adapter $adapter -JournalDirectory $dir
        Assert-Test ($restored.status -eq 'undone' -and $script:state[$key].value -is [int] -and
            $script:state[$key].value -eq $prior) "Undo restores exact signed DWORD $prior"
        $script:state.Clear()
    }

    $tx = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    $key = "$($rule.path)|$($rule.name)"
    $script:state[$key] = [pscustomobject]@{exists=$true;kind='DWord';value=7}
    $conflict = Invoke-UindosUndo -TransactionId $tx.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($conflict.status -eq 'needs-review' -and $conflict.conflicts -eq 1 -and $script:state[$key].value -eq 7) 'Undo detects drift and preserves it'
    $script:state[$key] = [pscustomobject]@{exists=$true;kind='DWord';value=1}
    $retry = Invoke-UindosUndo -TransactionId $tx.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($retry.status -eq 'undone' -and -not $script:state.ContainsKey($key)) 'Undo retry restores absent state after drift is resolved'

    $tx = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    $journalPath = Join-Path $dir "$($tx.transactionId).json"
    $bad = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json -Depth 20
    $bad.schema = 'tampered'
    $bad | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $journalPath
    Assert-Throws { Invoke-UindosUndo -TransactionId $tx.transactionId -Adapter $adapter -JournalDirectory $dir } 'Malformed journal identity rejected'

    $script:state[$key] = [pscustomobject]@{exists=$true;kind='String';value='1'}
    Assert-Throws { Get-UindosPlan -Actions $actions -Adapter $adapter } 'NonDWORD existing value rejected'
    $script:state.Clear()

    foreach ($invalid in @([long]2147483648,[long]-2147483649,'1',1.5,[decimal]1,$true,$null)) {
        Assert-Throws { ConvertTo-UindosSearchSuggestionsDword -Value $invalid } 'Invalid signed DWORD input rejected'
    }
    foreach ($mutant in @(
        [pscustomobject]@{id='search.disable-box-suggestions';path=$rule.path;name=$rule.name;kind='DWord';value=0},
        [pscustomobject]@{id='search.other';path=$rule.path;name=$rule.name;kind='DWord';value=1},
        [pscustomobject]@{id=$rule.id;path='HKLM:\SOFTWARE\Microsoft\Windows';name=$rule.name;kind='DWord';value=1},
        [pscustomobject]@{id=$rule.id;path=$rule.path;name=$rule.name;kind='QWord';value=1},
        [pscustomobject]@{id=$rule.id;path=$rule.path;name=$rule.name;kind='DWord';value='1'}
    )) { Assert-Throws { Get-UindosPlan -Actions @($mutant) -Adapter $adapter } 'Mutated action rejected' }
    Assert-Throws { & $adapter.Read 'HKLM:\Software\Policies\Microsoft\Windows\Explorer' $rule.name } 'Wrong read target rejected'
    Assert-Throws { & $adapter.Write $rule.path $rule.name 'QWord' 1 } 'Wrong write kind rejected'
    Assert-Throws { & $adapter.Write $rule.path 'OtherValue' 'DWord' 1 } 'Wrong write value name rejected'
    Assert-Throws { & $adapter.Remove $rule.path 'OtherValue' } 'Wrong remove target rejected'

    Write-Output 'PASS: Search suggestions allowlist, OS gate, dry-run/apply/idempotence, exact DWORD Undo, drift and malformed input rejection'
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedDir = [IO.Path]::GetFullPath($dir)
    if ($resolvedDir.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedDir) -match '^uindos-search-suggestions-mock-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedDir)) {
        Remove-Item -LiteralPath $resolvedDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
