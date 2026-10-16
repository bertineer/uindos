# Mock-only cross-platform Windows 11 taskbar visibility tests.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Taskbar.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
$os = [pscustomobject]@{editionId='Professional';build='26300';architecture='X64'}
$actions = @(Get-UindosTaskbarActions -OsInfo $os)
Assert-Test ($actions.Count -eq 3) 'three settings'
Assert-Test (@($actions | Where-Object { $_.kind -ne 'DWord' -or $_.value -ne 0 -or $_.path -notlike 'HKCU:*' }).Count -eq 0) 'only per-user DWORD zero preferences'
foreach ($required in @('TaskbarDa','ShowTaskViewButton','SearchboxTaskbarMode')) {
    Assert-Test (@($actions | Where-Object name -eq $required).Count -eq 1) "required setting $required"
}
foreach ($bad in @(
    [pscustomobject]@{editionId='Core';build='26300';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64'}
)) {
    $failed=$false
    try { [void]@(Get-UindosTaskbarActions -OsInfo $bad) }
    catch [System.NotSupportedException] { $failed=$true }
    Assert-Test $failed 'unsupported Windows blocked'
}
$script:state=@{}
$script:writes=0
$mock=@{
    ValidateAction={ param($a) Assert-UindosTaskbarAction -Action $a }
    Read={
        param($path,$name)
        Assert-UindosTaskbarTarget -Path $path -Name $name
        $key="$path|$name"
        if ($script:state.ContainsKey($key)) { return $script:state[$key] }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write={
        param($path,$name,$kind,$value)
        Assert-UindosTaskbarTarget -Path $path -Name $name
        if ($kind -cne 'DWord' -or [string]$value -cnotmatch '^[0-9]+$' -or [long]$value -gt [int]::MaxValue) {throw 'mock rejects unexpected writes'}
        $script:state["$path|$name"]=[pscustomobject]@{exists=$true;kind='DWord';value=[int]$value}
        $script:writes++
    }
    Remove={
        param($path,$name)
        Assert-UindosTaskbarTarget -Path $path -Name $name
        [void]$script:state.Remove("$path|$name")
        $script:writes++
    }
}
$dir=Join-Path ([IO.Path]::GetTempPath()) ("uindos-taskbar-"+[guid]::NewGuid().ToString('N'))
try {
    $plan=Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 3 -and $script:writes -eq 0 -and -not (Test-Path $dir)) 'preview only'
    $blocked=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) } catch { $blocked=$true }
    Assert-Test ($blocked -and $script:writes -eq 0) 'explicit apply required'
    $done=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($done.status -eq 'applied' -and $script:state.Count -eq 3) 'all three applied'
    $again=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($again.status -eq 'unchanged') 'idempotent'
    $undone=Invoke-UindosUndo -TransactionId $done.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undone.status -eq 'undone' -and $script:state.Count -eq 0) 'undo restores originally absent settings'
    $first="$($actions[0].path)|$($actions[0].name)"
    $script:state[$first]=[pscustomobject]@{exists=$true;kind='DWord';value=1}
    $second="$($actions[2].path)|$($actions[2].name)"
    $script:state[$second]=[pscustomobject]@{exists=$true;kind='DWord';value=2}
    $changed=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $restored=Invoke-UindosUndo -TransactionId $changed.transactionId -Adapter $mock -JournalDirectory $dir
    if ($restored.status -ne 'undone' -or $script:state[$first].value -ne 1 -or $script:state[$second].value -ne 2) {
        throw ('FAIL: prior values after undo; status={0}, conflicts={1}, first={2}, second={3}' -f $restored.status, $restored.conflicts, $script:state[$first].value, $script:state[$second].value)
    }
    $altered=[pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='DWord';value=1}
    $blocked=$false
    try { [void](Get-UindosPlan -Actions @($altered) -Adapter $mock) } catch { $blocked=$true }
    Assert-Test $blocked 'unapproved desired value blocked'
    Write-Output 'PASS: taskbar widgets/weather, search, task view current-user registry preview/apply/undo'
}
finally { if (Test-Path $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue } }
