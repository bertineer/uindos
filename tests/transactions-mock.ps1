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
$script:misreportName = $null
$script:misreportOnce = $false
$script:reads = 0
$script:writes = 0
$mock = @{
    Read = {
        param($Path, $Name)
        $script:reads++
        $key = "$Path|$Name"
        if ($Name -eq $script:misreportName -and $script:misreportOnce -and
            $script:store.ContainsKey($key) -and $script:store[$key].value -eq 'wanted') {
            $script:misreportOnce = $false
            return [pscustomobject]@{ exists = $true; kind = 'String'; value = 'temporary false observation' }
        }
        if ($script:store.ContainsKey($key)) { return $script:store[$key] }
        return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
    }
    Write = {
        param($Path, $Name, $Kind, $Value)
        if ($Name -eq $script:failName) {
            throw [UnauthorizedAccessException]::new("denied at $Path with private mock detail")
        }
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
    $failedSummary = $null
    try {
        [void](Invoke-UindosApply -Actions @($one, $two) -Adapter $mock -JournalDirectory $root -ConfirmChanges)
    }
    catch { $failedSummary = $_.Exception.Message }
    Assert-Test ($failedSummary -match 'action=test\.second stage=write exceptionType=UnauthorizedAccessException errorCode=access_denied') 'access failure reports safe action, stage, type and code'
    Assert-Test ($failedSummary -notmatch 'private mock detail|HKCU:|Mock') 'access failure summary omits exception message and registry path'
    Assert-Test ($script:store.Count -eq 1) 'first step automatically rolled back'
    Assert-Test ($script:store["$($one.path)|$($one.name)"].value -eq 17) 'rollback preserves original value'
    $script:failName = $null

    # A one-time incorrect observation triggers verification failure; the actual
    # desired value remains present so guarded rollback can safely restore prior state.
    $script:misreportName = 'First'
    $script:misreportOnce = $true
    $verificationSummary = $null
    try {
        [void](Invoke-UindosApply -Actions @($one) -Adapter $mock -JournalDirectory $root -ConfirmChanges)
    }
    catch { $verificationSummary = $_.Exception.Message }
    Assert-Test ($verificationSummary -match 'action=test\.first stage=verification exceptionType=InvalidOperationException errorCode=verification_failed') 'verification failure reports safe action, stage, type and code'
    Assert-Test ($verificationSummary -notmatch 'temporary false observation|HKCU:|Mock') 'verification failure summary omits value and registry path'
    Assert-Test ($script:store["$($one.path)|$($one.name)"].value -eq 17) 'verification failure safely rolls back prior value'
    $script:misreportName = $null

    # A journal failure during rollback must retain the original apply failure
    # and move the transaction to needs-review without exposing the fake path.
    $script:failName = 'Second'
    $script:journalSaveCalls = 0
    $script:originalJournalSave = ${function:Save-UindosJournal}
    Set-Item Function:\Save-UindosJournal -Value {
        param($Transaction, $Directory)
        $script:journalSaveCalls++
        if ($script:journalSaveCalls -eq 6) {
            throw [IO.IOException]::new('private journal path Z:\private\mock-journal.json')
        }
        & $script:originalJournalSave -Transaction $Transaction -Directory $Directory
    }
    $rollbackSummary = $null
    try {
        try {
            [void](Invoke-UindosApply -Actions @($one, $two) -Adapter $mock -JournalDirectory $root -ConfirmChanges)
        }
        catch { $rollbackSummary = $_.Exception.Message }
    }
    finally {
        Set-Item Function:\Save-UindosJournal -Value $script:originalJournalSave
        $script:failName = $null
    }
    Assert-Test ($rollbackSummary -match 'action=test\.second stage=write exceptionType=UnauthorizedAccessException errorCode=access_denied') 'rollback journal failure retains original apply diagnostics'
    Assert-Test ($rollbackSummary -match 'rollbackErrorCode=rollback_failed rollbackExceptionType=IOException') 'rollback journal failure reports safe type and code'
    Assert-Test ($rollbackSummary -match 'is needs-review' -and $rollbackSummary -notmatch 'private journal path|Z:\\private') 'failed rollback reports needs-review without leaking journal path'
    $failedId = [regex]::Match($rollbackSummary, 'transaction ([0-9a-f-]{36})').Groups[1].Value
    $failedJournal = Get-Content -LiteralPath (Join-Path $root "$failedId.json") -Raw | ConvertFrom-Json
    Assert-Test ($failedJournal.status -eq 'needs-review') 'needs-review status persisted after rollback journal failure'

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

    # Empty curated manifest is an entirely read-only, supported plan.
    $empty = Get-UindosPlan -Actions @() -Adapter $mock
    Assert-Test ($empty.changeCount -eq 0 -and $empty.actions.Count -eq 0) 'empty curated action list'

    # A competing process changes the value after snapshot but before the write.
    # Inject a modified observation on the adapter's second read.
    $script:store["$($one.path)|$($one.name)"] = [pscustomobject]@{
        exists = $true; kind = 'DWord'; value = 17
    }
    $script:raceReads = 0
    $race = @{
        Read = {
            param($Path, $Name)
            $script:raceReads++
            if ($script:raceReads -eq 2) {
                return [pscustomobject]@{ exists = $true; kind = 'String'; value = 'outside update' }
            }
            return $script:store["$Path|$Name"]
        }
        Write = { param($Path, $Name, $Kind, $Value) throw 'Writer must not run on drift.' }
        Remove = { param($Path, $Name) throw 'Remover must not run on drift.' }
    }
    $raceDetected = $false
    try {
        [void](Invoke-UindosApply -Actions @($one) -Adapter $race -JournalDirectory $root -ConfirmChanges)
    }
    catch { $raceDetected = $true }
    Assert-Test ($raceDetected -and $script:raceReads -ge 2) 'concurrent drift rejects write'
    Assert-Test ($script:store["$($one.path)|$($one.name)"].value -eq 17) 'drift rejection keeps prior state'

    $expandName = 'ExpandRaw'
    $expandKey = "$($one.path)|$expandName"
    $rawPrior = '%USERPROFILE%\before'
    $jsonValue = 'quoted "text" %TEMP%\folder\\雪'
    $script:store[$expandKey] = [pscustomobject]@{
        exists = $true; kind = 'ExpandString'; value = $rawPrior
    }
    $expandAction = New-TestAction -Id 'test.expand' -Name $expandName -Value $jsonValue -Kind 'ExpandString'
    $expandPlan = Get-UindosPlan -Actions @($expandAction) -Adapter $mock
    Assert-Test ($expandPlan.actions[0].prior.kind -eq 'ExpandString' -and
        $expandPlan.actions[0].prior.value -ceq $rawPrior) 'raw ExpandString prior state is captured'
    $expandTx = Invoke-UindosApply -Actions @($expandAction) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    Assert-Test ($expandTx.status -eq 'applied' -and
        $script:store[$expandKey].kind -eq 'ExpandString' -and
        $script:store[$expandKey].value -ceq $jsonValue) 'ExpandString applied without expanding percent tokens'
    $expandJournal = Get-Content -LiteralPath (Join-Path $root "$($expandTx.transactionId).json") -Raw | ConvertFrom-Json
    Assert-Test ($expandJournal.steps[0].prior.value -ceq $rawPrior -and
        $expandJournal.steps[0].desired.value -ceq $jsonValue) 'journal JSON preserves raw prior and escaped Unicode payload'
    $expandRepeat = Invoke-UindosApply -Actions @($expandAction) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    Assert-Test ($expandRepeat.status -eq 'unchanged') 'ExpandString repeat is unchanged'
    $script:store[$expandKey] = [pscustomobject]@{
        exists = $true; kind = 'String'; value = $jsonValue
    }
    $expandDrift = Invoke-UindosUndo -TransactionId $expandTx.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($expandDrift.status -eq 'needs-review' -and
        $script:store[$expandKey].kind -eq 'String') 'String and ExpandString drift are distinct'
    $script:store[$expandKey] = [pscustomobject]@{
        exists = $true; kind = 'ExpandString'; value = $jsonValue
    }
    $expandUndo = Invoke-UindosUndo -TransactionId $expandTx.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($expandUndo.status -eq 'undone' -and
        $script:store[$expandKey].kind -eq 'ExpandString' -and
        $script:store[$expandKey].value -ceq $rawPrior) 'undo restores exact raw ExpandString prior state'
    $script:store[$expandKey] = [pscustomobject]@{
        exists = $true; kind = 'ExpandString'; value = 17
    }
    $badPriorRejected = $false
    try { [void](Get-UindosPlan -Actions @($expandAction) -Adapter $mock) }
    catch { $badPriorRejected = $true }
    Assert-Test $badPriorRejected 'malformed non-string ExpandString prior value is rejected'
    $badExpandValueRejected = $false
    $badExpandAction = [pscustomobject]@{
        id = 'test.bad-expand'; path = $one.path; name = 'BadExpand'; kind = 'ExpandString'; value = 17
    }
    try { [void](Get-UindosPlan -Actions @($badExpandAction) -Adapter $mock) }
    catch { $badExpandValueRejected = $true }
    Assert-Test $badExpandValueRejected 'non-string desired ExpandString is rejected'
    $arrayExpandRejected = $false
    $badExpandAction.value = @('not', 'a', 'string')
    try { [void](Get-UindosPlan -Actions @($badExpandAction) -Adapter $mock) }
    catch { $arrayExpandRejected = $true }
    Assert-Test $arrayExpandRejected 'array desired ExpandString is rejected'
    foreach ($unsupportedKind in @('Binary', 'MultiString')) {
        $script:store["$($one.path)|UnsupportedPrior"] = [pscustomobject]@{
            exists = $true; kind = $unsupportedKind; value = 'unsupported'
        }
        $unsupportedAction = New-TestAction -Id ("test.unsupported." + $unsupportedKind.ToLowerInvariant()) -Name 'UnsupportedPrior' -Value 'safe'
        $unsupportedPriorRejected = $false
        try { [void](Get-UindosPlan -Actions @($unsupportedAction) -Adapter $mock) }
        catch { $unsupportedPriorRejected = $true }
        Assert-Test $unsupportedPriorRejected "$unsupportedKind prior registry type remains rejected"
        [void]$script:store.Remove("$($one.path)|UnsupportedPrior")
    }
    $writesBeforeBadRestore = $script:writes
    $badRestoreRejected = $false
    try {
        Set-UindosState -Adapter $mock -Action $expandAction -State ([pscustomobject]@{
            exists = $true; kind = 'ExpandString'; value = 17
        })
    }
    catch { $badRestoreRejected = $true }
    Assert-Test ($badRestoreRejected -and $script:writes -eq $writesBeforeBadRestore) 'malformed tampered ExpandString restore is rejected before write'
    [void]$script:store.Remove($expandKey)
    $script:store[$expandKey] = [pscustomobject]@{
        exists = $true; kind = 'String'; value = 'ordinary string prior'
    }
    $crossTypeTx = Invoke-UindosApply -Actions @($expandAction) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    $crossTypeUndo = Invoke-UindosUndo -TransactionId $crossTypeTx.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($crossTypeUndo.status -eq 'undone' -and
        $script:store[$expandKey].kind -eq 'String' -and
        $script:store[$expandKey].value -ceq 'ordinary string prior') 'undo restores String prior after ExpandString apply'
    [void]$script:store.Remove($expandKey)
    $absentExpandTx = Invoke-UindosApply -Actions @($expandAction) -Adapter $mock -JournalDirectory $root -ConfirmChanges
    $absentExpandUndo = Invoke-UindosUndo -TransactionId $absentExpandTx.transactionId -Adapter $mock -JournalDirectory $root
    Assert-Test ($absentExpandUndo.status -eq 'undone' -and -not $script:store.ContainsKey($expandKey)) 'ExpandString undo restores original absence'

    Write-Output 'PASS: mock transaction dry run, confirmation, idempotence, rollback, conflict and sandbox checks'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $fullRoot = [IO.Path]::GetFullPath($root)
    if (-not $fullRoot.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($fullRoot) -notmatch '^uindos-transaction-smoke-[0-9a-f]{32}$') {
        throw 'Refusing unsafe mock journal cleanup path.'
    }
    if (Test-Path -LiteralPath $fullRoot) { Remove-Item -LiteralPath $fullRoot -Force -Recurse -ErrorAction SilentlyContinue }
}
