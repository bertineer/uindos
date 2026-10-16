# Cross-platform mock-only tests. Does not touch Windows Registry or elevation.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Widgets.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }

$supported = [pscustomobject]@{editionId='Professional';build='26300';architecture='X64'}
$actions = @(Get-UindosWidgetsActions -OsInfo $supported)
Assert-Test ($actions.Count -eq 1 -and $actions[0].path -eq 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -and
    $actions[0].name -eq 'AllowNewsAndInterests' -and $actions[0].kind -eq 'DWord' -and $actions[0].value -eq 0) 'single documented policy action'
Assert-Test ((ConvertTo-UindosWidgetsDword 1) -eq 1) 'production DWORD guard permits exact prior value for Undo'
$badDword=$false
try { [void](ConvertTo-UindosWidgetsDword 2147483648) } catch [System.NotSupportedException] { $badDword=$true }
Assert-Test $badDword 'production DWORD guard rejects values outside the engine supported range'
foreach ($bad in @(
    [pscustomobject]@{editionId='Core';build='26300';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='22000';architecture='X86'},
    [pscustomobject]@{editionId='Enterprise';build='26300';architecture='Arm64'}
)) {
    $rejected=$false
    try { [void]@(Get-UindosWidgetsActions -OsInfo $bad) } catch [System.NotSupportedException] { $rejected=$true }
    Assert-Test $rejected 'unsupported edition/build/architecture rejected'
}

$script:state=@{}
$script:writes=0
$script:denyWrite=$false
$mock=@{
    ValidateAction={ param($Action) Assert-UindosWidgetsAction -Action $Action }
    Read={
        param($Path,$Name)
        Assert-UindosWidgetsTarget -Path $Path -Name $Name
        $key="$Path|$Name"
        if ($script:state.ContainsKey($key)) { return $script:state[$key] }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write={
        param($Path,$Name,$Kind,$Value)
        Assert-UindosWidgetsTarget -Path $Path -Name $Name
        if ($script:denyWrite) { throw [System.UnauthorizedAccessException]::new('mock denied') }
        if ($Kind -cne 'DWord') { throw 'unexpected mock write type' }
        $safeValue=ConvertTo-UindosWidgetsDword -Value $Value
        $script:state["$Path|$Name"]=[pscustomobject]@{exists=$true;kind='DWord';value=$safeValue}
        $script:writes++
    }
    Remove={
        param($Path,$Name)
        Assert-UindosWidgetsTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:writes++
    }
}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('uindos-widgets-'+[guid]::NewGuid().ToString('N'))
try {
    $plan=Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 1 -and $script:writes -eq 0 -and -not (Test-Path $dir)) 'read-only plan'
    $blocked=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) } catch { $blocked=$true }
    Assert-Test ($blocked -and $script:writes -eq 0) 'engine requires explicit apply'

    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $script:state.Count -eq 1) 'policy applies'
    Assert-Test ((Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges).status -eq 'unchanged') 'idempotent apply'
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state.Count -eq 0) 'undo restores prior absence'

    $key="$($actions[0].path)|$($actions[0].name)"
    $script:state[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=1}
    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state[$key].value -eq 1) 'undo restores prior DWORD value'

    $script:denyWrite=$true
    $failed=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges) } catch { $failed=$true }
    Assert-Test ($failed -and $script:state[$key].value -eq 1) 'denied write fails and preserves prior state'

    foreach ($mutant in @(
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='DWord';value=1},
        [pscustomobject]@{id=$actions[0].id;path='HKCU:\Software\Microsoft\Dsh';name=$actions[0].name;kind='DWord';value=0},
        [pscustomobject]@{id='widgets.other';path=$actions[0].path;name=$actions[0].name;kind='DWord';value=0}
    )) {
        $rejected=$false
        try { [void](Get-UindosPlan -Actions @($mutant) -Adapter $mock) } catch { $rejected=$true }
        Assert-Test $rejected 'action allowlist rejects modifications'
    }
    Write-Output 'PASS: supported Widgets policy gate, read-only plan, apply, idempotence, exact undo and denied-write rollback'
}
finally { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } }
