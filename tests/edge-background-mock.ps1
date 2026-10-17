# Cross-platform mock-only tests. Does not touch Windows Registry, Edge, or elevation.
param([string]$TestRoot = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\EdgeBackground.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }

$supported = [pscustomobject]@{editionId='Professional';build='26300';architecture='X64';edgeVersion='155.0.4283.60'}
$actions = @(Get-UindosEdgeBackgroundActions -OsInfo $supported)
Assert-Test ($actions.Count -eq 2) 'exactly two policies are managed'
Assert-Test (@($actions | Where-Object { $_.path -cne 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' }).Count -eq 0) 'machine Edge policy path'
Assert-Test (@($actions | Where-Object { $_.kind -cne 'DWord' -or $_.value -ne 0 }).Count -eq 0) 'both desired states are DWORD zero'
Assert-Test (@($actions.name | Sort-Object) -join ',' -ceq 'BackgroundModeEnabled,StartupBoostEnabled') 'exact allowlisted names'
Assert-Test ((ConvertTo-UindosEdgeBackgroundDword ([long]-2147483648)) -eq [int]::MinValue) 'Int64 journal restoration preserves signed DWORD boundary'
$badDword=$false
try { [void](ConvertTo-UindosEdgeBackgroundDword ([long]2147483648)) } catch [System.NotSupportedException] { $badDword=$true }
Assert-Test $badDword 'restoration conversion rejects values outside signed DWORD range'

$privatePath=Join-Path ([IO.Path]::GetTempPath()) ('uindos-edge-journal-'+[guid]::NewGuid().ToString('N'))
Assert-Test ((Get-UindosEdgeBackgroundJournalDirectory -JournalDirectory $privatePath -HasOverride $true -LocalAppData $null) -eq $privatePath) 'absolute journal override works without LOCALAPPDATA and does not create the directory'
$missingLocal=$false
try { [void](Get-UindosEdgeBackgroundJournalDirectory -HasOverride $false -LocalAppData '') } catch { $missingLocal=$true }
Assert-Test $missingLocal 'write-mode default journal requires LOCALAPPDATA'
$relativePath=$false
try { [void](Get-UindosEdgeBackgroundJournalDirectory -JournalDirectory 'relative\journal' -HasOverride $true -LocalAppData $null) } catch { $relativePath=$true }
Assert-Test $relativePath 'journal override must be absolute'
$unauthorized=$false
try { Assert-UindosEdgeBackgroundWriteAuthorization -IsAdministrator $false } catch { $unauthorized=$true }
Assert-Test $unauthorized 'write authorization fails closed without an existing elevated process'
Assert-UindosEdgeBackgroundWriteAuthorization -IsAdministrator $true

foreach ($bad in @(
    [pscustomobject]@{editionId='Core';build='26300';architecture='X64';edgeVersion='155.0.4283.60'},
    [pscustomobject]@{editionId='Professional';build='19045';architecture='X64';edgeVersion='155.0.4283.60'},
    [pscustomobject]@{editionId='Professional';build='26300';architecture='X86';edgeVersion='155.0.4283.60'},
    [pscustomobject]@{editionId='Enterprise';build='26300';architecture='Arm64';edgeVersion='155.0.4283.60'},
    [pscustomobject]@{editionId='Professional';build='26300';architecture='X64';edgeVersion='87.0.0.0'},
    [pscustomobject]@{editionId='Professional';build='26300';architecture='X64';edgeVersion='not-a-version'}
)) {
    $rejected=$false
    try { [void]@(Get-UindosEdgeBackgroundActions -OsInfo $bad) } catch [System.NotSupportedException] { $rejected=$true }
    Assert-Test $rejected 'unsupported edition/build/architecture/Edge version rejected'
}

$script:state=@{}
$script:writes=0
$script:denyName=$null
$mock=@{
    ValidateAction={ param($Action) Assert-UindosEdgeBackgroundAction -Action $Action }
    Read={
        param($Path,$Name)
        Assert-UindosEdgeBackgroundTarget -Path $Path -Name $Name
        $key="$Path|$Name"
        if ($script:state.ContainsKey($key)) {
            if ($script:state[$key].kind -cne 'DWord') {
                throw [System.NotSupportedException]::new('Mock refuses an existing non-DWORD Edge policy value.')
            }
            return $script:state[$key]
        }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write={
        param($Path,$Name,$Kind,$Value)
        Assert-UindosEdgeBackgroundTarget -Path $Path -Name $Name
        if ($script:denyName -ceq $Name) { throw [System.UnauthorizedAccessException]::new('mock denied') }
        if ($Kind -cne 'DWord') { throw 'unexpected mock write type' }
        $safeValue=ConvertTo-UindosEdgeBackgroundDword -Value $Value
        $script:state["$Path|$Name"]=[pscustomobject]@{exists=$true;kind='DWord';value=$safeValue}
        $script:writes++
    }
    Remove={
        param($Path,$Name)
        Assert-UindosEdgeBackgroundTarget -Path $Path -Name $Name
        [void]$script:state.Remove("$Path|$Name")
        $script:writes++
    }
}
$dir=Join-Path $TestRoot ('uindos-edge-background-'+[guid]::NewGuid().ToString('N'))
try {
    $plan=Get-UindosPlan -Actions $actions -Adapter $mock
    Assert-Test ($plan.changeCount -eq 2 -and $script:writes -eq 0 -and -not (Test-Path $dir)) 'read-only plan has no journal effect'
    $blocked=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir) } catch { $blocked=$true }
    Assert-Test ($blocked -and $script:writes -eq 0) 'engine requires explicit apply'

    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $script:state.Count -eq 2) 'both policies apply'
    Assert-Test ((Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges).status -eq 'unchanged') 'repeat apply is idempotent'
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state.Count -eq 0) 'undo restores prior absence'

    $script:state["$($actions[0].path)|$($actions[0].name)"]=[pscustomobject]@{exists=$true;kind='DWord';value=1L}
    $script:state["$($actions[1].path)|$($actions[1].name)"]=[pscustomobject]@{exists=$true;kind='DWord';value=2}
    $applied=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $undo=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:state["$($actions[0].path)|$($actions[0].name)"].value -eq 1 -and
        $script:state["$($actions[1].path)|$($actions[1].name)"].value -eq 2) 'undo restores exact prior DWORD values, including journal Int64'

    $badKindKey="$($actions[0].path)|$($actions[0].name)"
    $script:state[$badKindKey]=[pscustomobject]@{exists=$true;kind='String';value='0'}
    $wrongKind=$false
    try { [void](Get-UindosPlan -Actions $actions -Adapter $mock) } catch { $wrongKind=$true }
    Assert-Test $wrongKind 'wrong existing registry kind fails closed'
    $script:state[$badKindKey]=[pscustomobject]@{exists=$true;kind='DWord';value=1}

    $script:denyName='BackgroundModeEnabled'
    $failed=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges) } catch { $failed=$true }
    Assert-Test ($failed -and $script:state[$badKindKey].value -eq 1 -and
        $script:state["$($actions[1].path)|$($actions[1].name)"].value -eq 2) 'failed second write rolls back the first policy'
    $script:denyName=$null

    $drift=Invoke-UindosApply -Actions $actions -Adapter $mock -JournalDirectory $dir -ConfirmChanges
    $driftKey="$($actions[0].path)|$($actions[0].name)"
    $script:state[$driftKey]=[pscustomobject]@{exists=$true;kind='DWord';value=3}
    $driftUndo=Invoke-UindosUndo -TransactionId $drift.transactionId -Adapter $mock -JournalDirectory $dir
    Assert-Test ($driftUndo.status -eq 'needs-review' -and $script:state[$driftKey].value -eq 3) 'undo preserves externally drifted policy and requests review'

    foreach ($mutant in @(
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name=$actions[0].name;kind='DWord';value=1},
        [pscustomobject]@{id=$actions[0].id;path='HKCU:\Software\Policies\Microsoft\Edge';name=$actions[0].name;kind='DWord';value=0},
        [pscustomobject]@{id='edge.other';path=$actions[0].path;name=$actions[0].name;kind='DWord';value=0},
        [pscustomobject]@{id=$actions[0].id;path=$actions[0].path;name='DoNotAllowEdgeUpdate';kind='DWord';value=0}
    )) {
        $rejected=$false
        try { [void](Get-UindosPlan -Actions @($mutant) -Adapter $mock) } catch { $rejected=$true }
        Assert-Test $rejected 'action allowlist rejects changed values and out-of-scope targets'
    }
    Write-Output 'PASS: Edge background policy gate, exact targets, journal paths, read-only plan, apply, repeat, exact undo, rollback, wrong-kind, drift, and allowlist'
}
finally {
    if (Test-Path -LiteralPath $dir) {
        # Only the engine's flat transaction files are removed; never recurse.
        Get-ChildItem -LiteralPath $dir -File -Force | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force
        }
        [IO.Directory]::Delete([IO.Path]::GetFullPath($dir), $false)
    }
}
