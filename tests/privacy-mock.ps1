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
        if ($Kind -cne 'DWord') { throw 'Mock write must be DWORD.' }
        $safeValue = ConvertTo-UindosPrivacyDword -Value $Value
        $script:state["$Path|$Name"] = [pscustomobject]@{ exists = $true; kind = $Kind; value = $safeValue }
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

    # Existing values need a Write during Undo, unlike originally absent ones.
    # Exercise disk JSON reload, including both ends of the signed DWORD range.
    foreach ($priorValue in @(7, [int]::MinValue, [int]::MaxValue, -1)) {
        $script:state[$key] = [pscustomobject]@{ exists = $true; kind = 'DWord'; value = $priorValue }
        $existing = Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
        $journal = Get-Content -LiteralPath (Join-Path $dir "$($existing.transactionId).json") -Raw | ConvertFrom-Json -Depth 20
        Assert-Test ($journal.steps[0].prior.value -is [long]) 'Saved prior DWORD reloads as Int64'
        $restored = Invoke-UindosUndo -TransactionId $existing.transactionId -Adapter $mock -JournalDirectory $dir
        Assert-Test ($restored.status -eq 'undone' -and $restored.conflicts -eq 0) 'Existing DWORD Undo succeeds'
        Assert-Test ($script:state[$key].value -is [int] -and $script:state[$key].value -eq $priorValue) 'Exact signed DWORD restored'
        Assert-Test ($script:state.Count -eq 1) 'Other originally absent values removed'
        $script:state.Clear()
    }

    foreach ($invalid in @([long]2147483648, [long]-2147483649, '1', 1.5, [decimal]1, $true, $null)) {
        $rejected = $false
        try { [void](ConvertTo-UindosPrivacyDword -Value $invalid) } catch { $rejected = $true }
        Assert-Test $rejected 'Out-of-range or non-integer prior values rejected'
    }

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

    Write-Output 'PASS: curated privacy defaults, OS gate, dry run, idempotence, prior-DWORD JSON undo, guarded undo and allowlist'
}
finally {
    $resolvedRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $resolvedDir = [IO.Path]::GetFullPath($dir)
    if ($resolvedDir.StartsWith($resolvedRoot, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedDir) -match '^uindos-privacy-mock-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedDir)) {
        Remove-Item -LiteralPath $resolvedDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
