# Portable orchestration tests. All registry/export/context operations are mocks.
param([string]$TestRoot=[IO.Path]::GetTempPath())
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\StartResetWorkflow.ps1')
function Assert-Test { param([bool]$Condition,[string]$Message) if(-not $Condition){throw "FAIL: $Message"} }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $failed=$false; try{& $Action | Out-Null}catch{$failed=$true}; Assert-Test $failed $Message }
$script:state=@{}
$script:writes=0
$script:removes=0
$script:exports=0
$script:failEnable=$false
$script:observations=[pscustomobject]@{domainJoined=$false;cloudJoinPresent=$false;mdmAccountsPresent=$false;userGpoPresent=$false;machineGpoPresent=$false
    probeComplete=$true;hkcuLayoutPolicyPresent=$false;hkcuOtherLayoutPolicyPresent=$false;hklmLayoutPolicyPresent=$false;mdmStartPolicyPresent=$false}
function Assert-UindosStartResetContext { param([switch]$RequireElevation) [pscustomobject]@{ownerSid='S-1-5-21-1000';sessionId=1;elevated=[bool]$RequireElevation} }
function Get-UindosStartResetActions { @(Get-UindosStartResetCatalog) }
function Get-UindosStartResetGuardData { $script:observations }
function New-UindosStartResetAdapter {
    @{
        ValidateAction={param($action) Assert-UindosStartResetAction $action}
        Read={param($path,$name) if($script:state.ContainsKey($name)){$script:state[$name]}else{[pscustomobject]@{exists=$false;kind=$null;value=$null}}}
        Write={param($path,$name,$kind,$value)
            if($script:failEnable -and $name -eq 'ConfigureStartPins'){throw 'Injected enable write failure'}
            $script:writes++;$script:state[$name]=[pscustomobject]@{exists=$true;kind=$kind;value=$value}}
        Remove={param($path,$name) $script:removes++;$script:state.Remove($name)}
    }
}
function Get-UindosStartPinsPreflight {
    param([string]$PrivateExportDirectory,[switch]$AllowElevatedPolicyPreflight)
    $script:exports++
    if($PrivateExportDirectory){
        [void][IO.Directory]::CreateDirectory($PrivateExportDirectory)
        [IO.File]::WriteAllText((Join-Path $PrivateExportDirectory 'layout.json'),'{"pinnedList":[{"packagedAppId":"5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App"}]}')
        [IO.File]::WriteAllText((Join-Path $PrivateExportDirectory 'families.json'),'{"packageFamilies":[],"context":{"elevated":true,"sameUserAsExplorer":true}}')
    }
    [pscustomobject]@{report=[pscustomobject]@{startPinCount=1}}
}
$parent=[IO.Path]::GetFullPath($TestRoot).TrimEnd('\','/')
$root=Join-Path $parent ('uindos-start-reset-test-'+[Guid]::NewGuid().ToString('D'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $op=Join-Path $root 'operation'
    $fakeRepo=Join-Path $root 'repo'
    [void][IO.Directory]::CreateDirectory((Join-Path $fakeRepo '.git'))
    Assert-Throws {Resolve-UindosStartResetDirectory (Join-Path $fakeRepo 'private')} 'Private exports refused inside a Git worktree'
    Assert-Throws {Invoke-UindosStartReset -Mode Apply -StateDirectory $op} 'Acknowledgment required'
    Assert-Test (-not [IO.Directory]::Exists($op) -and $script:exports -eq 0) 'Missing acknowledgment has no backup or write effects'
    $preview=Invoke-UindosStartReset
    Assert-Test ($preview.mode -eq 'read-only' -and $preview.status -eq 'ready-for-acknowledged-apply' -and $script:writes -eq 0) 'Preview uses read-only dependencies'
    $script:observations.probeComplete=$false
    Assert-Test ((Invoke-UindosStartReset).status -eq 'blocked') 'Incomplete preview is blocked'
    Assert-Throws {Invoke-UindosStartReset -Mode Apply -StateDirectory $op -AcknowledgeLayoutReset} 'Unknown authority blocks before artifacts'
    Assert-Test (-not [IO.Directory]::Exists($op)) 'Blocked Apply creates no operation'
    $script:observations.probeComplete=$true
    $result=Invoke-UindosStartReset -Mode Apply -StateDirectory $op -AcknowledgeLayoutReset
    Assert-Test ($result.status -eq 'applied' -and $result.policyVerified -and -not $result.layoutVerified -and $result.previousPinCount -eq 1) 'Apply reports policy and layout separately'
    Assert-Test ($script:writes -eq 2 -and $script:state.Count -eq 2) 'Only two policy values written'
    $tx=Get-UindosStartResetOperation -Directory $op -OwnerSid 'S-1-5-21-1000' -TransactionId $result.transactionId
    Assert-Test ($tx.steps[0].action.name -eq 'ConfigureStartPinsJSON' -and $tx.steps[1].action.name -eq 'ConfigureStartPins') 'Payload precedes enable flag'
    $beforeExports=$script:exports
    $script:observations.hkcuLayoutPolicyPresent=$true
    $repeat=Invoke-UindosStartReset -Mode Apply -StateDirectory $op -AcknowledgeLayoutReset
    Assert-Test ($repeat.status -eq 'unchanged' -and $script:writes -eq 2 -and $script:exports -eq $beforeExports) 'Owned repeat has no new writes/export/journal'
    $script:observations.hkcuOtherLayoutPolicyPresent=$true
    Assert-Throws {Invoke-UindosStartReset -Mode Apply -StateDirectory $op -AcknowledgeLayoutReset} 'Owned pair does not waive unrelated HKCU layout policy'
    $script:observations.hkcuOtherLayoutPolicyPresent=$false
    $other=Join-Path $root 'other'
    Assert-Throws {Invoke-UindosStartReset -Mode Apply -StateDirectory $other -AcknowledgeLayoutReset} 'New operation cannot adopt an existing pair'
    Assert-Test (-not [IO.Directory]::Exists($other)) 'Unowned pair rejected before evidence'
    Assert-Throws {Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $op -TransactionId ([Guid]::NewGuid().ToString('D'))} 'Wrong transaction cannot undo'
    $metadataPath=Join-Path $op 'operation.json'
    $originalMetadata=[IO.File]::ReadAllText($metadataPath)
    $wrongOwner=$originalMetadata.Replace('S-1-5-21-1000','S-1-5-21-9999')
    [IO.File]::WriteAllText($metadataPath,$wrongOwner)
    Assert-Throws {Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $op -TransactionId $result.transactionId} 'Other owner rejected'
    [IO.File]::WriteAllText($metadataPath,$originalMetadata)
    $backupPath=Join-Path $op 'backup/layout.json'
    $originalBackup=[IO.File]::ReadAllText($backupPath)
    [IO.File]::WriteAllText($backupPath,'{}')
    Assert-Throws {Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $op -TransactionId $result.transactionId} 'Changed private backup requires review'
    [IO.File]::WriteAllText($backupPath,$originalBackup)
    $journalPath=Join-Path $op ('transactions/'+$result.transactionId+'.json')
    $originalJournal=[IO.File]::ReadAllText($journalPath)
    [IO.File]::WriteAllText($journalPath,$originalJournal.Replace('start.enable-pins-policy','start.invalid-action'))
    Assert-Throws {Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $op -TransactionId $result.transactionId} 'Malformed scoped journal rejected'
    [IO.File]::WriteAllText($journalPath,$originalJournal)
    function Get-UindosStartResetActions { throw 'Unsupported build after update' }
    $script:observations.domainJoined=$true
    $undo=Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $op -TransactionId $result.transactionId
    Assert-Test ($undo.status -eq 'undone' -and -not $undo.layoutRestored -and $script:state.Count -eq 0 -and $script:removes -eq 2) 'Policy-only Undo works after OS/management changes and removes owned pair only'
    Assert-Test ($script:exports -eq $beforeExports) 'Undo does not overwrite or apply exported pins'
    Assert-Test ((Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $op -TransactionId $result.transactionId).status -eq 'undone') 'Policy Undo repeat is safe'
    function Get-UindosStartResetActions { @(Get-UindosStartResetCatalog) }
    $script:observations.domainJoined=$false;$script:observations.hkcuLayoutPolicyPresent=$false
    $script:failEnable=$true
    $failedOp=Join-Path $root 'failed'
    Assert-Throws {Invoke-UindosStartReset -Mode Apply -StateDirectory $failedOp -AcknowledgeLayoutReset} 'Second write failure surfaces'
    Assert-Test ($script:state.Count -eq 0) 'Enable failure rolls back payload'
    $failedTx=Get-UindosStartResetOperation -Directory $failedOp -OwnerSid 'S-1-5-21-1000'
    Assert-Test ($failedTx.status -eq 'rolled-back') 'Interrupted linking remains discoverable through sole journal'
    $script:failEnable=$false
    $driftOp=Join-Path $root 'drift'
    $driftResult=Invoke-UindosStartReset -Mode Apply -StateDirectory $driftOp -AcknowledgeLayoutReset
    $script:state.ConfigureStartPins=[pscustomobject]@{exists=$true;kind='DWord';value=0}
    Assert-Throws {Invoke-UindosStartReset -Mode Apply -StateDirectory $driftOp -AcknowledgeLayoutReset} 'Owned pair drift refuses repeat'
    $driftUndo=Invoke-UindosStartReset -Mode UndoPolicy -StateDirectory $driftOp -TransactionId $driftResult.transactionId
    Assert-Test ($driftUndo.status -eq 'needs-review' -and $script:state.ConfigureStartPins.value -eq 0 -and -not $script:state.ContainsKey('ConfigureStartPinsJSON')) 'Guarded Undo preserves drift and reports conflict'
    $initial=New-UindosStartResetInitialAdapter -Adapter (New-UindosStartResetAdapter)
    Assert-Throws {& $initial.Read 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'ConfigureStartPins'} 'Policy arriving before engine snapshot cannot become accepted prior'
    # The same per-user mutex excludes two operation directories.
    $lock=Enter-UindosStartResetLock 'S-1-5-21-1000'
    try {
        $probe=[powershell]::Create()
        try {
            [void]$probe.AddScript({param($module,$sid)
                . $module
                try {$otherLock=Enter-UindosStartResetLock $sid;try{'acquired'}finally{$otherLock.ReleaseMutex();$otherLock.Dispose()}}
                catch {'blocked'}
            }).AddArgument((Join-Path $PSScriptRoot '..\src\foundation\StartResetWorkflow.ps1')).AddArgument('S-1-5-21-1000')
            $probeResult=@($probe.Invoke())
            Assert-Test ($probeResult.Count -eq 1 -and $probeResult[0] -eq 'blocked') 'Another thread cannot acquire the same per-SID mutation mutex'
        } finally {$probe.Dispose()}
    } finally {$lock.ReleaseMutex();$lock.Dispose()}
    Write-Output 'PASS: Start reset preview, acknowledgment, ownership, backup/journal validation, apply/repeat, scoped Undo, failure rollback and drift'
} finally {
    $full=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetDirectoryName($full).TrimEnd('\','/') -ne $parent -or
        [IO.Path]::GetFileName($full) -notmatch '^uindos-start-reset-test-[0-9a-f-]{36}$'){throw 'Unsafe test cleanup path'}
    [IO.Directory]::Delete($full,$true)
}
