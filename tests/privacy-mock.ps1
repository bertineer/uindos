# Cross-platform, mock-only privacy default tests. Does not touch the registry.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Privacy.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$fakeOs = [pscustomobject]@{ editionId = 'Professional'; build = '26100'; architecture = 'X64' }
$actions = @(Get-UindosPrivacyActions -OsInfo $fakeOs)
Assert-Test ($actions.Count -eq 3) 'Exactly three opinionated rules'
Assert-Test ((@($actions | Where-Object { $_.value -eq 1 })).Count -eq 2) 'Two disabled suggestion policies'
Assert-Test ((@($actions | Where-Object { $_.value -eq 0 })).Count -eq 1) 'Advertising ID preference is zero'
Assert-Test ((@($actions | Where-Object { $_.path -notlike 'HKCU:*' })).Count -eq 0) 'Current user only'

foreach ($unsupported in @(
    [pscustomobject]@{ editionId = 'Core'; build = '26100'; architecture = 'X64' },
    [pscustomobject]@{ editionId = 'Enterprise'; build = '26100'; architecture = 'X64' },
    [pscustomobject]@{ editionId = 'Professional'; build = '19045'; architecture = 'X64' },
    [pscustomobject]@{ editionId = 'Professional'; build = '26100'; architecture = 'X86' }
)) {
    $rejected = $false
    try { [void]@(Get-UindosPrivacyActions -OsInfo $unsupported) }
    catch [System.NotSupportedException] { $rejected = $true }
    Assert-Test $rejected "Unsupported OS rejected ($($unsupported.editionId)/$($unsupported.build))"
}

$script:state = @{}
$script:changes = 0
$mock = @{
    ValidateAction = { param($Action) Assert-UindosPrivacyAction -Action $Action }
    Read = {
        param($Path,$Name)
        Assert-UindosPrivacyTarget -Path $Path -Name $Name
        $key = "$Path|$Name"
        if ($script:state.ContainsKey($key)) { return $script:state[$key] }
        return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
    }
    Write = {
        param($Path,$Name,$Kind,$Value)
        Assert-UindosPrivacyTarget -Path $Path -Name $Name
        if ($Kind -cne 'DWord' -or $Value -isnot [int]) { throw 'Mock write must be DWORD.' }
        $script:state["$Path|$Name"] = [pscustomobject]@{ exists = $true; kind = $Kind; value = $Value }
        $script:changes++
    }
    Remove = {
        param($Path,$Name)
        Assert-UindosPrivacyTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:changes++
    }
}

$dir = Join-Path ([IO.Path]::GetTempPath()) ('uindos-privacy-mock-' + [Guid]::NewGuid().ToString('N'))
try {
    $plan = Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 3) 'Three planned changes'
    Assert-Test ($script:changes -eq 0 -and -not (Test-Path $dir)) 'Dry-run zero writes'

    $blocked = $false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) }
    catch { $blocked = $true }
    Assert-Test ($blocked -and $script:changes -eq 0) 'No unconfirmed apply'

    $result = Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($result.status -eq 'applied' -and $script:state.Count -eq 3) 'All three values applied'
    $again = Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($again.status -eq 'unchanged') 'Repeated apply no-op'

    $undo = Invoke-UindosUndo -TransactionId $result.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state.Count -eq 0) 'Restores originally absent values'

    $result = Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $key = "$($actions[0].path)|$($actions[0].name)"
    $script:state[$key] = [pscustomobject]@{ exists = $true; kind = 'DWord'; value = 7 }
    $conflict = Invoke-UindosUndo -TransactionId $result.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($conflict.status -eq 'needs-review' -and $conflict.conflicts -eq 1) 'Drift reported'
    Assert-Test ($script:state[$key].value -eq 7) 'User drift not overwritten'
    $script:state[$key] = [pscustomobject]@{ exists = $true; kind = 'DWord'; value = 1 }
    $retried = Invoke-UindosUndo -TransactionId $result.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($retried.status -eq 'undone' -and $script:state.Count -eq 0) 'Recoverable conflict retry'

    $mutants = @(
        [pscustomobject]@{ id='privacy.tailored-experiences'; path=$actions[0].path; name=$actions[0].name; kind='DWord'; value=0 },
        [pscustomobject]@{ id='privacy.malicious'; path=$actions[0].path; name=$actions[0].name; kind='DWord'; value=1 },
        [pscustomobject]@{ id='privacy.third-party-suggestions'; path='HKLM:\SOFTWARE\Microsoft\Windows'; name='DisableThirdPartySuggestions'; kind='DWord'; value=1 }
    )
    foreach ($mutant in $mutants) {
        $rejected = $false
        try { [void](Get-UindosPlan -Actions @($mutant) -Adapter $mock) }
        catch { $rejected = $true }
        Assert-Test $rejected 'Modified action denied'
    }

    Write-Output 'PASS: curated privacy defaults, OS gate, dry run, idempotence, guarded undo and allowlist'
}
finally {
    if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}
