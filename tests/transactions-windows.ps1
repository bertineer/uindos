# Windows-only integration. Writes only under an ephemeral HKCU uindos test key.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This integration test requires Windows.' }
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Description)
    if (-not $Condition) { throw "FAIL: $Description" }
}

$token = [Guid]::NewGuid().ToString('N')
$key = "HKCU:\Software\uindos\EngineTest\CI-$token"
$journal = Join-Path ([IO.Path]::GetTempPath()) "uindos-ci-journal-$token"
$adapter = New-UindosRegistryAdapter
$action = [pscustomobject]@{ id='test.registry'; path=$key; name='Value'; kind='DWord'; value=7 }
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

    Write-Output 'PASS: live Windows HKCU sandbox apply, verify, idempotence and rollback'
}
finally {
    # Test-only cleanup: remove ONLY the random child test key and local test files.
    if (Test-Path -LiteralPath $key) { Remove-Item -LiteralPath $key -Recurse -Force }
    if (Test-Path -LiteralPath $journal) { Remove-Item -LiteralPath $journal -Recurse -Force }
}
