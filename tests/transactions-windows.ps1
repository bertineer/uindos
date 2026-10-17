# Windows-only integration. Writes only under an ephemeral HKCU uindos test key.
param([string]$JournalRoot = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This integration test requires Windows.' }
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAIL: $Description" }
}

$token = [Guid]::NewGuid().ToString('N')
$key = "HKCU:\Software\uindos\EngineTest\CI-$token"
if (-not [IO.Path]::IsPathRooted($JournalRoot)) { throw 'JournalRoot must be an absolute path.' }
$resolvedJournalRoot = [IO.Path]::GetFullPath($JournalRoot)
if ($resolvedJournalRoot -ne [IO.Path]::GetPathRoot($resolvedJournalRoot)) {
    $resolvedJournalRoot = $resolvedJournalRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)
}
$journal = Join-Path $resolvedJournalRoot "uindos-ci-journal-$token"
$adapter = New-UindosRegistryAdapter
$action = [pscustomobject]@{ id='test.registry'; path=$key; name='Value'; kind='DWord'; value=7 }
$expandName = "UINDOS_EXPAND_TEST_$token"
$processEnvironment = [Environment]::GetEnvironmentVariables('Process')
$hadExpandEnv = $processEnvironment.Contains($expandName)
$oldExpandEnv = if ($hadExpandEnv) { [string]$processEnvironment[$expandName] } else { $null }
try {
    $before = & $adapter.Read $key 'Value'
    Assert-Test (-not $before.exists) 'initially absent'
    $p = Get-UindosPlan -Actions @($action) -Adapter $adapter
    Assert-Test ($p.changeCount -eq 1) 'read-only plan'
    Assert-Test (-not (Test-Path $key) -and -not (Test-Path $journal)) 'plan has no side effects'

    $applied = Invoke-UindosApply -Actions @($action) -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied') 'apply status'
    $after = & $adapter.Read $key 'Value'
    Assert-Test ($after.exists -and $after.kind -eq 'DWord' -and $after.value -eq 7) 'registry value changed'

    $repeat = Invoke-UindosApply -Actions @($action) -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
    Assert-Test ($repeat.status -eq 'unchanged') 'idempotent real registry operation'

    $reverted = Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $adapter -JournalDirectory $journal
    Assert-Test ($reverted.status -eq 'undone') 'undo outcome'
    Assert-Test (-not (& $adapter.Read $key 'Value').exists) 'original absence restored'
    Assert-Test ((Get-Content (Join-Path $journal "$($applied.transactionId).json") -Raw | ConvertFrom-Json).status -eq 'undone') 'journal finalized'

    [Environment]::SetEnvironmentVariable($expandName, 'before', 'Process')
    $expandPayload = '%' + $expandName + '%\quoted "value"\\雪'
    $expand = [pscustomobject]@{ id='test.expand'; path=$key; name='Expand'; kind='ExpandString'; value=$expandPayload }
    & $adapter.Write $key 'Expand' 'ExpandString' "%$expandName%\before"
    $expandBefore = & $adapter.Read $key 'Expand'
    Assert-Test ($expandBefore.kind -eq 'ExpandString' -and $expandBefore.value -ceq "%$expandName%\before") 'adapter reads raw unexpanded ExpandString'
    $expandApplied = Invoke-UindosApply -Actions @($expand) -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
    $expandAfter = & $adapter.Read $key 'Expand'
    Assert-Test ($expandApplied.status -eq 'applied' -and $expandAfter.kind -eq 'ExpandString' -and $expandAfter.value -ceq $expand.value) 'ExpandString raw value and type applied'
    $expandRepeat = Invoke-UindosApply -Actions @($expand) -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
    Assert-Test ($expandRepeat.status -eq 'unchanged') 'ExpandString repeat unchanged'
    $keyHandle = Get-Item -LiteralPath $key
    try { $expandedControl = $keyHandle.GetValue('Expand') }
    finally { $keyHandle.Dispose() }
    Assert-Test ($expandedControl -ceq 'before\quoted "value"\\雪') 'ordinary RegistryKey.GetValue expands environment token as control'
    [Environment]::SetEnvironmentVariable($expandName, 'after', 'Process')
    $expandUndo = Invoke-UindosUndo -TransactionId $expandApplied.transactionId -Adapter $adapter -JournalDirectory $journal
    $expandRestored = & $adapter.Read $key 'Expand'
    Assert-Test ($expandUndo.status -eq 'undone' -and $expandRestored.kind -eq 'ExpandString' -and
        $expandRestored.value -ceq "%$expandName%\before") 'undo restores exact raw prior after environment changes'

    Write-Output 'PASS: live Windows HKCU sandbox apply, verify, idempotence and rollback'
}
finally {
    [Environment]::SetEnvironmentVariable($expandName, $(if ($hadExpandEnv) { $oldExpandEnv } else { $null }), 'Process')
    # Test-only cleanup is restricted to this exact random CI child and GUID directory below JournalRoot.
    if ($key -match '^HKCU:\\Software\\uindos\\EngineTest\\CI-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $key)) {
        Remove-Item -LiteralPath $key -Recurse -Force
    }
    $fullJournal = [IO.Path]::GetFullPath($journal)
    $journalRootPrefix = if ($resolvedJournalRoot.EndsWith([IO.Path]::DirectorySeparatorChar)) {
        $resolvedJournalRoot
    } else { $resolvedJournalRoot + [IO.Path]::DirectorySeparatorChar }
    if ($fullJournal.StartsWith($journalRootPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($fullJournal) -match '^uindos-ci-journal-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $fullJournal)) {
        Remove-Item -LiteralPath $fullJournal -Recurse -Force
    }
}
