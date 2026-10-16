# Portable transaction and allowlist tests for the curated dark-mode defaults.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Theme.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
$os = [pscustomobject]@{editionId='Professional';build='26300';architecture='X64'}
$actions = @(Get-UindosThemeActions -OsInfo $os)
Assert-Test ($actions.Count -eq 2) 'two theme preferences'
Assert-Test (@($actions | Where-Object { $_.path -cne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -or $_.kind -cne 'DWord' -or $_.value -ne 0 }).Count -eq 0) 'only curated per-user DWORD zero values'
Assert-Test (@($actions | Where-Object name -ceq 'AppsUseLightTheme').Count -eq 1) 'app dark-mode preference'
Assert-Test (@($actions | Where-Object name -ceq 'SystemUsesLightTheme').Count -eq 1) 'system dark-mode preference'
foreach ($bad in @(
    [pscustomobject]@{editionId='Core';build='26300';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64'},
    [pscustomobject]@{editionId='Professional';build='26300';architecture='Arm'}
)) {
    $blocked=$false
    try { [void]@(Get-UindosThemeActions -OsInfo $bad) } catch [System.NotSupportedException] { $blocked=$true }
    Assert-Test $blocked 'unsupported Windows platform blocked'
}
$altered=[pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='DWord';value=1}
$blocked=$false
try { Assert-UindosThemeAction -Action $altered } catch [System.NotSupportedException] { $blocked=$true }
Assert-Test $blocked 'unapproved value blocked'
$blocked=$false
try { Assert-UindosThemeTarget -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' } catch [System.NotSupportedException] { $blocked=$true }
Assert-Test $blocked 'unapproved target blocked'

$script:state=@{}
$script:writes=0
$mock=@{
    ValidateAction={ param($a) Assert-UindosThemeAction -Action $a }
    Read={
        param($path,$name)
        Assert-UindosThemeTarget -Path $path -Name $name
        $key="$path|$name"
        if ($script:state.ContainsKey($key)) { return $script:state[$key] }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write={
        param($path,$name,$kind,$value)
        Assert-UindosThemeTarget -Path $path -Name $name
        if ($kind -cne 'DWord') { throw 'mock rejects unexpected registry kind' }
        $number=ConvertTo-UindosThemeDword -Value $value
        $script:state["$path|$name"]=[pscustomobject]@{exists=$true;kind='DWord';value=$number}
        $script:writes++
    }
    Remove={
        param($path,$name)
        Assert-UindosThemeTarget -Path $path -Name $name
        [void]$script:state.Remove("$path|$name")
        $script:writes++
    }
}
$tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$dir=Join-Path $tempRoot ("uindos-theme-"+[guid]::NewGuid().ToString('N'))
try {
    $plan=Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 2 -and $script:writes -eq 0 -and -not (Test-Path -LiteralPath $dir)) 'preview is read-only'
    $blocked=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) } catch { $blocked=$true }
    Assert-Test ($blocked -and $script:writes -eq 0) 'explicit apply required'

    $absent=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($absent.status -eq 'applied' -and $script:state.Count -eq 2) 'dark-mode values applied'
    $again=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($again.status -eq 'unchanged') 'apply is idempotent'
    $undoAbsent=Invoke-UindosUndo -TransactionId $absent.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undoAbsent.status -eq 'undone' -and $script:state.Count -eq 0) 'undo restores original absence'

    foreach ($action in $actions) {
        $script:state["$($action.path)|$($action.name)"]=[pscustomobject]@{exists=$true;kind='DWord';value=1}
    }
    $priorTx=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $journal=Get-Content -Raw -LiteralPath (Join-Path $dir "$($priorTx.transactionId).json") | ConvertFrom-Json -Depth 20
    Assert-Test ($journal.steps[0].prior.value -is [long]) 'JSON DWORD prior value deserializes as Int64'
    $undoPrior=Invoke-UindosUndo -TransactionId $priorTx.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undoPrior.status -eq 'undone') 'Int64 journal value safely restores'
    foreach ($action in $actions) {
        Assert-Test ($script:state["$($action.path)|$($action.name)"].value -eq 1) "exact prior DWORD restored: $($action.name)"
    }

    $driftTx=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $driftKey="$($actions[0].path)|$($actions[0].name)"
    $script:state[$driftKey]=[pscustomobject]@{exists=$true;kind='DWord';value=2}
    $driftUndo=Invoke-UindosUndo -TransactionId $driftTx.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($driftUndo.status -eq 'needs-review' -and $script:state[$driftKey].value -eq 2) 'undo preserves drift and reports conflict'
    Assert-Test ($script:state["$($actions[1].path)|$($actions[1].name)"].value -eq 1) 'undo restores unchanged action despite other drift'

    $malformedTx=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $malformedPath=Join-Path $dir "$($malformedTx.transactionId).json"
    $malformed=Get-Content -Raw -LiteralPath $malformedPath | ConvertFrom-Json -Depth 20
    $malformed.steps[0].prior.kind='Binary'
    [IO.File]::WriteAllText($malformedPath,(ConvertTo-Json -InputObject $malformed -Depth 20),[Text.UTF8Encoding]::new($false))
    $malformedUndo=Invoke-UindosUndo -TransactionId $malformedTx.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($malformedUndo.status -eq 'needs-review') 'malformed journal type rejected safely'
    Write-Output 'PASS: theme allowlist, preview/apply, absence and Int64 DWORD Undo, drift, malformed journal'
}
finally {
    $resolvedRoot=[IO.Path]::GetFullPath($tempRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    $resolvedDir=[IO.Path]::GetFullPath($dir)
    if ($resolvedDir.StartsWith($resolvedRoot,[StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedDir) -match '^uindos-theme-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedDir)) {
        Remove-Item -LiteralPath $resolvedDir -Recurse -Force
    }
}
