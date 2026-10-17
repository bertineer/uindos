# Preview-first, one-operation Start reset. This journals policy values only;
# the exported layout is evidence, not a promise of layout reconstruction.
. (Join-Path $PSScriptRoot '..\core\Transactions.ps1')
. (Join-Path $PSScriptRoot 'StartReset.ps1')
. (Join-Path $PSScriptRoot 'StartPinsPreflight.ps1')

function Resolve-UindosStartResetDirectory {
    param([string]$Directory)
    if ([string]::IsNullOrWhiteSpace($Directory) -or -not [IO.Path]::IsPathFullyQualified($Directory)) {
        throw 'Start reset needs an absolute private StateDirectory.'
    }
    $full = [IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
    if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\','/')) { throw 'StateDirectory cannot be a filesystem root.' }
    $ancestor = $full
    while (-not [string]::IsNullOrEmpty($ancestor)) {
        if (Test-Path -LiteralPath (Join-Path $ancestor '.git')) { throw 'Keep private Start reset evidence outside Git worktrees.' }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
    return $full
}

function Enter-UindosStartResetLock {
    param([string]$OwnerSid)
    if ($OwnerSid -notmatch '^S-1-[0-9-]+$') { throw 'Invalid desktop user identity.' }
    # HKCU is shared by every session for this SID; Local would permit races
    # between separate desktop sessions using separate operation directories.
    $mutex = [Threading.Mutex]::new($false, "Global\uindos.start-reset.$OwnerSid")
    $owned = $false
    try {
        try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) { throw 'Another Start reset policy command is active for this user.' }
        return $mutex
    } catch { $mutex.Dispose(); throw }
}

function New-UindosStartResetInitialAdapter {
    param([hashtable]$Adapter)
    # The engine captures its own fresh plan. Do not let an external policy that
    # appears after our guard become a newly accepted prior value in that plan.
    $reader = $Adapter.Read
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $result = $Adapter.Clone()
    $result.Read = {
        param($path,$name)
        $state = & $reader $path $name
        if ($seen.Add("$path|$name") -and $state.exists) { throw 'Start policy appeared before the transaction snapshot.' }
        return $state
    }.GetNewClosure()
    return $result
}

function Get-UindosStartResetOperation {
    param([string]$Directory, [string]$OwnerSid, [string]$TransactionId)
    $metadataPath = Join-Path $Directory 'operation.json'
    if (-not [IO.File]::Exists($metadataPath)) { throw 'Existing StateDirectory has no Start reset metadata; refusing it.' }
    $metadata = [IO.File]::ReadAllText($metadataPath) | ConvertFrom-Json -Depth 20
    $operationGuid = [Guid]::Empty
    if ($metadata.schema -cne 'uindos.start-reset-operation/v1' -or
        $metadata.ownerSid -cne $OwnerSid -or $metadata.acknowledgedLayoutReset -isnot [bool] -or
        -not $metadata.acknowledgedLayoutReset -or
        -not [Guid]::TryParseExact([string]$metadata.id,'D',[ref]$operationGuid)) {
        throw 'Start reset metadata identity, owner or acknowledgment is invalid.'
    }
    foreach ($entry in @(@('layout.json','layoutSha256'),@('families.json','familiesSha256'))) {
        $path = Join-Path $Directory ('backup/' + $entry[0])
        $expected = [string]$metadata.($entry[1])
        if ($expected -notmatch '^[A-Fa-f0-9]{64}$' -or -not [IO.File]::Exists($path) -or
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $expected) {
            throw 'Private Start reset backup is missing or changed; review the operation before proceeding.'
        }
    }
    $journals = @(Get-ChildItem -LiteralPath (Join-Path $Directory 'transactions') -Filter '*.json' -File -ErrorAction Stop)
    if ($journals.Count -ne 1) { throw 'Expected exactly one policy transaction in this operation; inspect private evidence.' }
    $guid = [Guid]::Empty
    if (-not [Guid]::TryParseExact($journals[0].BaseName,'D',[ref]$guid)) { throw 'Invalid policy journal filename.' }
    $tx = [IO.File]::ReadAllText($journals[0].FullName) | ConvertFrom-Json -Depth 20
    if ($tx.schema -cne 'uindos.transaction/v1' -or $tx.id -cne $guid.ToString('D') -or
        (-not [string]::IsNullOrEmpty($TransactionId) -and $tx.id -cne $TransactionId) -or
        $tx.steps -isnot [array] -or $tx.steps.Count -ne 2 -or
        $tx.status -cnotin @('prepared','applying','applied','rolling-back','rolled-back','needs-review','undoing','undone')) {
        throw 'Start reset policy journal identity or state is invalid.'
    }
    $catalog = @(Get-UindosStartResetCatalog)
    for ($i=0; $i -lt 2; $i++) {
        $step = $tx.steps[$i]
        Assert-UindosStartResetAction -Action $step.action
        $desired = [pscustomobject]@{exists=$true; kind=$catalog[$i].kind; value=$catalog[$i].value}
        if ($step.action.id -cne $catalog[$i].id -or $step.desired.exists -isnot [bool] -or -not $step.desired.exists -or
            -not (Test-UindosStateEqual $step.desired $desired) -or
            $step.prior.exists -isnot [bool] -or $step.prior.exists -or
            $step.changeRequired -isnot [bool] -or -not $step.changeRequired -or
            $step.phase -cnotin @('prepared','writing','applied','restored','conflict')) {
            throw 'Policy journal is not the fixed, initially absent Start reset operation.'
        }
    }
    return $tx
}

function Invoke-UindosStartReset {
    [CmdletBinding()]
    param([ValidateSet('Preview','Apply','UndoPolicy')][string]$Mode='Preview',
          [string]$StateDirectory, [string]$TransactionId, [switch]$AcknowledgeLayoutReset)
    # Reject missing consent before creating backup directories or acquiring a lock.
    if ($Mode -eq 'Apply' -and -not $AcknowledgeLayoutReset) {
        throw 'Apply requires -AcknowledgeLayoutReset: policy Undo cannot restore the pin layout, including missing-app pins.'
    }
    $context = Assert-UindosStartResetContext -RequireElevation:($Mode -ne 'Preview')
    $adapter = New-UindosStartResetAdapter
    $behaviorNote = 'Policy verification is not layout verification. Check Start separately; activation or persistence checks may require a coordinated sign-in. UndoPolicy restores policy values only; original pins may not be recoverable.'
    if ($Mode -eq 'Preview') {
        $actions = @(Get-UindosStartResetActions)
        $guard = Test-UindosStartResetGuard -Observations (Get-UindosStartResetGuardData)
        $inventory = Get-UindosStartPinsPreflight -AllowElevatedPolicyPreflight
        # Do not print raw prior policy contents or private backup paths.
        return [pscustomobject]@{schema='uindos.start-reset/v1'; mode='read-only'; status=if($guard.allowed){'ready-for-acknowledged-apply'}else{'blocked'}
            guard=$guard; pins=$inventory.report; desiredPolicy=$actions; behaviorNote=$behaviorNote}
    }
    $directory = Resolve-UindosStartResetDirectory $StateDirectory
    if ($Mode -eq 'UndoPolicy') {
        $parsed = [Guid]::Empty
        if (-not [Guid]::TryParseExact($TransactionId,'D',[ref]$parsed)) { throw 'UndoPolicy requires a canonical transaction GUID.' }
    } else { $actions = @(Get-UindosStartResetActions) }
    $mutex = Enter-UindosStartResetLock -OwnerSid $context.ownerSid
    try {
        $journalDirectory = Join-Path $directory 'transactions'
        if ([IO.Directory]::Exists($directory)) {
            $tx = Get-UindosStartResetOperation -Directory $directory -OwnerSid $context.ownerSid -TransactionId $TransactionId
            if ($Mode -eq 'UndoPolicy') {
                $result = Invoke-UindosUndo -TransactionId $tx.id -Adapter $adapter -JournalDirectory $journalDirectory
                return [pscustomobject]@{schema='uindos.start-reset/v1'; mode='undo-policy'; status=$result.status
                    transactionId=$result.transactionId; conflicts=$result.conflicts; layoutRestored=$false; behaviorNote=$behaviorNote}
            }
            if ($tx.status -cne 'applied') { throw 'This operation cannot be reapplied; review its journal or use UndoPolicy.' }
            $plan = Get-UindosPlan -Actions $actions -Adapter $adapter
            if ($plan.changeCount -ne 0) { throw 'Owned Start policy has drifted; refusing repeat Apply.' }
            $guard = Test-UindosStartResetGuard -Observations (Get-UindosStartResetGuardData) -AllowOwnedPolicy
            if (-not $guard.allowed) { throw ('Start reset blocked: ' + ($guard.reasons -join ', ')) }
            return [pscustomobject]@{schema='uindos.start-reset/v1'; mode='apply'; status='unchanged'; transactionId=$tx.id
                policyVerified=$true; layoutVerified=$false; behaviorNote=$behaviorNote}
        }
        if ($Mode -eq 'UndoPolicy') { throw 'UndoPolicy StateDirectory does not exist.' }
        if ([IO.File]::Exists($directory)) { throw 'StateDirectory names an existing file.' }
        $guard = Test-UindosStartResetGuard -Observations (Get-UindosStartResetGuardData)
        if (-not $guard.allowed) { throw ('Start reset blocked: ' + ($guard.reasons -join ', ')) }
        $plan = Get-UindosPlan -Actions $actions -Adapter $adapter
        if (@($plan.actions | Where-Object { $_.prior.exists }).Count -ne 0) { throw 'Existing Start policy is not owned by this operation.' }
        # A new directory is reserved atomically. Never overwrite a previous operation.
        $parent = [IO.Path]::GetDirectoryName($directory)
        if (-not [IO.Directory]::Exists($parent)) { throw 'Create the private parent directory first.' }
        $reservation = [IO.File]::Open(($directory + '.reserve'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            if ([IO.Directory]::Exists($directory) -or [IO.File]::Exists($directory)) { throw 'StateDirectory appeared while reserving it.' }
            [void][IO.Directory]::CreateDirectory($directory)
        } finally { $reservation.Dispose(); [IO.File]::Delete(($directory + '.reserve')) }
        $backup = Join-Path $directory 'backup'
        $inventory = Get-UindosStartPinsPreflight -PrivateExportDirectory $backup -AllowElevatedPolicyPreflight
        $metadata = [pscustomobject]@{schema='uindos.start-reset-operation/v1'; id=[Guid]::NewGuid().ToString('D')
            ownerSid=$context.ownerSid; createdUtc=[DateTime]::UtcNow.ToString('o'); acknowledgedLayoutReset=$true
            layoutSha256=(Get-FileHash -LiteralPath (Join-Path $backup 'layout.json') -Algorithm SHA256).Hash
            familiesSha256=(Get-FileHash -LiteralPath (Join-Path $backup 'families.json') -Algorithm SHA256).Hash}
        $metadataPath = Join-Path $directory 'operation.json'
        [IO.File]::WriteAllText(($metadataPath + '.tmp'),(ConvertTo-Json -InputObject $metadata -Depth 5),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move(($metadataPath + '.tmp'),$metadataPath)
        # Recheck authority and absence immediately before the engine snapshots/writes.
        $guard = Test-UindosStartResetGuard -Observations (Get-UindosStartResetGuardData)
        if (-not $guard.allowed) { throw ('Start reset blocked after backup: ' + ($guard.reasons -join ', ')) }
        $plan = Get-UindosPlan -Actions $actions -Adapter $adapter
        if (@($plan.actions | Where-Object { $_.prior.exists }).Count -ne 0) { throw 'Start policy appeared after backup; refusing to overwrite it.' }
        $initialAdapter = New-UindosStartResetInitialAdapter -Adapter $adapter
        $result = Invoke-UindosApply -Actions $actions -Adapter $initialAdapter -JournalDirectory $journalDirectory -ConfirmChanges
        $verified = (Get-UindosPlan -Actions $actions -Adapter $adapter).changeCount -eq 0
        if (-not $verified) { throw 'Start policy pair changed after Apply; inspect the private journal and use guarded UndoPolicy.' }
        return [pscustomobject]@{schema='uindos.start-reset/v1'; mode='apply'; status=$result.status; transactionId=$result.transactionId
            policyVerified=$true; layoutVerified=$false; previousPinCount=$inventory.report.startPinCount; behaviorNote=$behaviorNote}
    } finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}
