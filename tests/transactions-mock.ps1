# Portable mock-only transaction tests (PowerShell 7, no real OS changes).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAIL: $Description" }
}

function New-TestAction {
    param([string]$Id, [string]$Name, [string]$Value, [string]$Kind = 'String')
    return [pscustomobject]@{
        id = $Id
        path = 'HKCU:\Software\uindos\EngineTest\Mock'
        name = $Name
        kind = $Kind
        value = $Value
    }
}

$script:store = @{}
$script:failName = $null
$script:reads = 0
$script:writes = 0
$mock = @{
    Read = {
        param($Path, $Name)
        $script:reads++
        $key = "$Path|$Name"
        if ($script:store.ContainsKey($key)) { return $script:store[$key] }
        return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
    }
    Write = {
        param($Path, $Name, $Kind, $Value)
        if ($Name -eq $script:failName) { throw 'Simulated writer failure.' }
        $script:writes++
        $script:store["$Path|$Name"] = [pscustomobject]@{
            exists = $true; kind = $Kind; value = $Value
        }
    }
    Remove = {
        param($Path, $Name)
        $script:writes++
        [void]$script:store.Remove("$Path|$Name")
    }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('uindos-transaction-smoke-' + [Guid]::NewGuid().ToString('N'))
$one = New-TestAction -Id 'test.first' -Name 'First' -Value 'wanted'
$two = New-TestAction -Id 'test.second' -Name 'Second' -Value 'needed'
try {
    $plan = Get-UindosPlan -Actions @($one) -Adapter $mock
    Assert-Test ($plan.schema -eq 'uindos.plan/v1' -and $plan.changeCount -eq 1) 'plan reports change'
    Assert-Test ($script:writes -eq 0 -and -not (Test-Path $root)) 'plan does not write or create journal'
    Assert-Test ($plan.actions[0].prior.exists -eq $false) 'absent prior state captured'

    $denied = $false
    try { [void](Invoke-UindosApply -Actions @($one) -Adapter $mock -JournalDirectory $root) }
    catch { $denied = $true }
    Assert-Test ($denied -and $script:writes -eq 0) 'explicit confirmation required'

    $tx = Invoke-UindosApply -Actions @($one) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    Assert-Test ($tx.status -eq 'applied' -and $script:writes -eq 1) 'applied once'
    Assert-Test (Test-Path (Join-Path $root "$($tx.transactionId).json")) 'journal created'
    Assert-Test ($script:store.Count -eq 1) 'mock target exists'

    $again = Invoke-UindosApply -Actions @($one) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    Assert-Test ($again.status -eq 'unchanged' -and $script:writes -eq 1) 'idempotent repeated apply'
    Assert-Test ($again.transactionId -eq $null) 'no journal needed for no-op'

    $undo = Invoke-UindosUndo -TransactionId $tx.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($undo.status -eq 'undone' -and $script:store.Count -eq 0) 'removed originally absent value'
    $undoAgain = Invoke-UindosUndo -TransactionId $tx.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($undoAgain.status -eq 'undone') 'undo idempotent'

    $script:store["$($one.path)|$($one.name)"] = [pscustomobject]@{
        exists = $true; kind = 'DWord'; value = 17
    }
    $setNew = Invoke-UindosApply -Actions @($one) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    Assert-Test ($script:store["$($one.path)|$($one.name)"].kind -eq 'String') 'type switched'
    $back = Invoke-UindosUndo -TransactionId $setNew.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($back.status -eq 'undone') 'existing value restored'
    $restored = $script:store["$($one.path)|$($one.name)"]
    Assert-Test ($restored.kind -eq 'DWord' -and $restored.value -eq 17) 'prior type and value intact'

    $multi = Invoke-UindosApply -Actions @($one,$two) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    Assert-Test ($multi.changeCount -eq 2) 'multi-step apply'
    $script:store["$($two.path)|$($two.name)"] = [pscustomobject]@{
        exists = $true; kind = 'String'; value = 'changed outside uindos'
    }
    $drift = Invoke-UindosUndo -TransactionId $multi.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($drift.status -eq 'needs-review' -and $drift.conflicts -eq 1) 'drift causes conflict'
    Assert-Test ($script:store["$($two.path)|$($two.name)"].value -eq 'changed outside uindos') 'drift not clobbered'
    Assert-Test ($script:store["$($one.path)|$($one.name)"].value -eq 17) 'other step safely restored'

    # After returning the drifted value to expected, a retry can finish undo.
    $script:store["$($two.path)|$($two.name)"] = [pscustomobject]@{
        exists = $true; kind = 'String'; value = 'needed'
    }
    $retry = Invoke-UindosUndo -TransactionId $multi.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($retry.status -eq 'undone' -and $script:store.Count -eq 1) 'retry resolves conflict'

    $script:failName = 'Second'
    $failed = $false
    try {
        [void](Invoke-UindosApply -Actions @($one, $two) -Adapter $mock -JournalDirectory $root -ConfirmChanges)
    }
    catch { $failed = $true }
    Assert-Test $failed 'apply failure surfaced'
    Assert-Test ($script:store.Count -eq 1) 'first step automatically rolled back'
    Assert-Test ($script:store["$($one.path)|$($one.name)"].value -eq 17) 'rollback preserves original value'
    $script:failName = $null

    $dupe = $false
    try { [void](Get-UindosPlan -Actions @($one,$one) -Adapter $mock) }
    catch { $dupe = $true }
    Assert-Test $dupe 'duplicate action IDs rejected'

    $other = New-TestAction -Id 'test.other' -Name 'First' -Value 'conflict'
    $dupeTarget = $false
    try { [void](Get-UindosPlan -Actions @($one,$other) -Adapter $mock) }
    catch { $dupeTarget = $true }
    Assert-Test $dupeTarget 'duplicate targets rejected'

    $outside = New-TestAction -Id 'test.outside' -Name 'Disabled' -Value '1'
    $outside.path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies'
    $disallowed = $false
    try { [void](Get-UindosPlan -Actions @($outside) -Adapter $mock) }
    catch { $disallowed = $true }
    Assert-Test $disallowed 'sensitive registry locations denied'

    $parsedJournals = @(Get-ChildItem $root -Filter '*.json')
    Assert-Test ($parsedJournals.Count -ge 3) 'journals persisted'
    foreach ($file in $parsedJournals) {
        $doc = Get-Content $file.FullName -Raw | ConvertFrom-Json
        Assert-Test ($doc.schema -eq 'uindos.transaction/v1') 'journal schema valid'
    }

    Write-Output 'PASS: mock transaction dry run, confirmation, idempotence, rollback, conflict and sandbox checks'
}
finally {
    if (Test-Path $root) { Remove-Item -LiteralPath $root -Force -Recurse -ErrorAction SilentlyContinue }
}
