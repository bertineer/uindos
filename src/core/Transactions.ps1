# Transaction engine for curated uindos state changes.
# M3 initially supported only the EngineTest sandbox; adapters may now supply
# strict ValidateAction rules for individually reviewed privacy values.
# No arbitrary commands, package removal, service edits or unsigned scripts.
. (Join-Path $PSScriptRoot 'RegistryAdapter.ps1')

function Assert-UindosAdapter {
    param([hashtable]$Adapter)
    if ($null -eq $Adapter) { throw 'A trusted adapter is required.' }
    foreach ($method in @('Read', 'Write', 'Remove')) {
        if (-not $Adapter.ContainsKey($method) -or $Adapter[$method] -isnot [scriptblock]) {
            throw "Adapter missing trusted '$method' operation."
        }
    }
    if ($Adapter.ContainsKey('ValidateAction') -and $Adapter.ValidateAction -isnot [scriptblock]) {
        throw 'Adapter ValidateAction must be a scriptblock.'
    }
}

function ConvertTo-UindosAction {
    param([Parameter(Mandatory)]$Action, [AllowNull()][hashtable]$Adapter)
    $id = [string]$Action.id
    $path = [string]$Action.path
    $name = [string]$Action.name
    $kind = [string]$Action.kind
    if ($id -cnotmatch '^[a-z][a-z0-9._-]{2,79}$') { throw 'Invalid action identifier.' }
    if ($name -cnotmatch '^[a-zA-Z0-9_.-]{1,120}$') { throw 'Invalid registry value name.' }
    if ($null -ne $Adapter -and $Adapter.ContainsKey('ValidateAction')) {
        & $Adapter.ValidateAction $Action
    }
    else {
        # Backward compatible sandbox-only behavior for test adapters.
        Assert-UindosSandboxRegistryPath -Path $path
    }
    if ($kind -cnotin @('String', 'DWord', 'QWord')) { throw 'Invalid action registry kind.' }

    $value = $Action.value
    if ($null -eq $value) { throw 'Null desired value is not supported.' }
    if ($kind -eq 'String') {
        if ($value -isnot [string]) { throw 'String registry kind requires a string value.' }
    }
    else {
        $digits = [string]$value
        if ($digits -notmatch '^[0-9]+$') { throw 'Numeric registry values must be unsigned integer digits.' }
        [long]$number = 0
        if (-not [long]::TryParse($digits, [ref]$number)) { throw 'Registry integer exceeds supported range.' }
        if ($kind -eq 'DWord' -and $number -gt [int]::MaxValue) {
            throw 'M3 DWORD must be <= 2147483647.'
        }
        $value = if ($kind -eq 'DWord') { [int]$number } else { [long]$number }
    }
    return [pscustomobject]@{ id = $id; path = $path; name = $name; kind = $kind; value = $value }
}

function Test-UindosStateEqual {
    param($Left, $Right)
    if ([bool]$Left.exists -ne [bool]$Right.exists) { return $false }
    if (-not [bool]$Left.exists) { return $true }
    if ([string]$Left.kind -cne [string]$Right.kind) { return $false }
    return ([string]$Left.value -ceq [string]$Right.value)
}

function Get-UindosPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Actions,
          [Parameter(Mandatory)][hashtable]$Adapter)
    Assert-UindosAdapter -Adapter $Adapter
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $targets = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $steps = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $Actions) {
        $a = ConvertTo-UindosAction -Action $candidate -Adapter $Adapter
        if (-not $ids.Add($a.id)) { throw 'Duplicate action ID.' }
        if (-not $targets.Add("$($a.path)|$($a.name)")) { throw 'Duplicate registry target.' }
        $prior = & $Adapter.Read $a.path $a.name
        if ($null -eq $prior) { throw 'Read operation returned no state.' }
        if ($prior.exists -and $prior.kind -notin @('String','DWord','QWord')) {
            throw 'Cannot capture unsupported prior registry type.'
        }
        $desired = [pscustomobject]@{ exists = $true; kind = $a.kind; value = $a.value }
        $change = -not (Test-UindosStateEqual -Left $prior -Right $desired)
        $steps.Add([pscustomobject]@{
            action = $a
            prior = $prior
            desired = $desired
            phase = if ($change) { 'prepared' } else { 'unchanged' }
            changeRequired = $change
        })
    }
    return [pscustomobject]@{
        schema = 'uindos.plan/v1'
        mode = 'read-only'
        actions = @($steps.ToArray())
        changeCount = @($steps | Where-Object changeRequired).Count
    }
}

function Save-UindosJournal {
    param([Parameter(Mandatory)]$Transaction,
          [Parameter(Mandatory)][string]$Directory)
    $file = Join-Path $Directory "$($Transaction.id).json"
    $temporary = Join-Path $Directory ".$($Transaction.id).$([Guid]::NewGuid().ToString('N')).tmp"
    $json = ConvertTo-Json -InputObject $Transaction -Depth 20
    try {
        [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        # Same-directory rename/replace: a crash retains either old or new journal.
        [IO.File]::Move($temporary, $file, $true)
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
    return $file
}

function Enter-UindosJournalLock {
    param([string]$Directory)
    [void][IO.Directory]::CreateDirectory($Directory)
    # Exclusive local lock; never modify state while another transaction is active.
    return [IO.File]::Open((Join-Path $Directory '.lock'),
        [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
}

function Set-UindosState {
    param([hashtable]$Adapter, $Action, $State)
    if ($State.exists) {
        & $Adapter.Write $Action.path $Action.name $State.kind $State.value
    }
    else {
        & $Adapter.Remove $Action.path $Action.name
    }
}

function Restore-UindosSteps {
    param($Transaction, [hashtable]$Adapter, [string]$Directory)
    $conflicts = 0
    for ($i = $Transaction.steps.Count - 1; $i -ge 0; $i--) {
        $step = $Transaction.steps[$i]
        if ($step.phase -in @('prepared', 'unchanged', 'restored')) { continue }
        if ($step.phase -notin @('writing', 'applied', 'conflict')) {
            $step.phase = 'conflict'
            $conflicts++
            [void](Save-UindosJournal -Transaction $Transaction -Directory $Directory)
            continue
        }
        try {
            # Revalidate journal paths: never trust a disk file to expand write scope.
            $a = ConvertTo-UindosAction -Action $step.action -Adapter $Adapter
            $current = & $Adapter.Read $a.path $a.name
            if (Test-UindosStateEqual -Left $current -Right $step.prior) {
                $step.phase = 'restored'
            }
            elseif (Test-UindosStateEqual -Left $current -Right $step.desired) {
                Set-UindosState -Adapter $Adapter -Action $a -State $step.prior
                $observed = & $Adapter.Read $a.path $a.name
                if (-not (Test-UindosStateEqual -Left $observed -Right $step.prior)) {
                    throw 'Restored state failed verification.'
                }
                $step.phase = 'restored'
            }
            else {
                # The user/application changed the setting after apply: don't overwrite it.
                $step.phase = 'conflict'
                $conflicts++
            }
        }
        catch {
            $step.phase = 'conflict'
            $conflicts++
        }
        [void](Save-UindosJournal -Transaction $Transaction -Directory $Directory)
    }
    return $conflicts
}

function Invoke-UindosApply {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][array]$Actions,
          [Parameter(Mandatory)][hashtable]$Adapter,
          [Parameter(Mandatory)][string]$JournalDirectory,
          [switch]$ConfirmChanges)

    Assert-UindosAdapter -Adapter $Adapter
    if (-not $ConfirmChanges) {
        throw 'Apply requires explicit -ConfirmChanges. Use Get-UindosPlan for dry-run.'
    }
    $lock = Enter-UindosJournalLock -Directory $JournalDirectory
    try {
        # Re-read all values under lock; a stale plan is never trusted.
        $plan = Get-UindosPlan -Actions $Actions -Adapter $Adapter
        if ($plan.changeCount -eq 0) {
            return [pscustomobject]@{ status = 'unchanged'; transactionId = $null; changeCount = 0 }
        }
        $tx = [pscustomobject]@{
            schema = 'uindos.transaction/v1'
            id = [Guid]::NewGuid().ToString()
            createdUtc = [DateTime]::UtcNow.ToString('o')
            status = 'prepared'
            steps = @($plan.actions)
        }
        # This must succeed before changing any registry value.
        try { [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory) }
        catch {
            $journalExceptionType = $_.Exception.GetType().Name
            throw "Apply failed; transaction $($tx.id) remains prepared. action=none stage=journal exceptionType=$journalExceptionType errorCode=journal_failure."
        }
        $failureStage = 'journal'
        $failedActionId = $null
        try {
            $tx.status = 'applying'
            $failureStage = 'journal'
            [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
            foreach ($step in $tx.steps) {
                if (-not $step.changeRequired) { continue }
                $failedActionId = $step.action.id
                # Another program may change the value between planning and this step.
                # Refuse to overwrite state we did not snapshot.
                $failureStage = 'pre-write-read'
                $preWrite = & $Adapter.Read $step.action.path $step.action.name
                if ($null -eq $preWrite -or
                    -not (Test-UindosStateEqual -Left $preWrite -Right $step.prior)) {
                    throw 'State changed after snapshot; refusing to overwrite drift.'
                }
                $step.phase = 'writing'
                $failureStage = 'journal'
                [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
                $failureStage = 'write'
                Set-UindosState -Adapter $Adapter -Action $step.action -State $step.desired
                $failureStage = 'verification'
                $observed = & $Adapter.Read $step.action.path $step.action.name
                if (-not (Test-UindosStateEqual -Left $observed -Right $step.desired)) {
                    throw [InvalidOperationException]::new('Post-change verification failed.')
                }
                $step.phase = 'applied'
                $failureStage = 'journal'
                [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
            }
            $tx.status = 'applied'
            $failureStage = 'journal'
            [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
            return [pscustomobject]@{ status = 'applied'; transactionId = $tx.id; changeCount = $plan.changeCount }
        }
        catch {
            # Snapshot a safe summary before rollback can produce a different error.
            $originalException = $_.Exception
            while (($originalException -is [System.Management.Automation.MethodInvocationException] -or
                    $originalException -is [System.Management.Automation.RuntimeException]) -and
                   $null -ne $originalException.InnerException) {
                $originalException = $originalException.InnerException
            }
            $originalType = $originalException.GetType().Name
            $errorCode = if ($failureStage -eq 'journal') { 'journal_failure' }
                elseif ($failureStage -eq 'pre-write-read') { 'pre_write_read_failed' }
                elseif ($failureStage -eq 'verification') { 'verification_failed' }
                elseif ($originalException -is [System.UnauthorizedAccessException]) { 'access_denied' }
                elseif ($originalException -is [System.IO.IOException]) { 'io_failure' }
                else { 'operation_failed' }
            $safeActionId = if ($null -eq $failedActionId) { 'none' } else { [string]$failedActionId }
            $safeStage = [string]$failureStage
            $tx.status = 'rolling-back'
            $rollbackExceptionType = $null
            try {
                [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
                $conflicts = Restore-UindosSteps -Transaction $tx -Adapter $Adapter -Directory $JournalDirectory
                $tx.status = if ($conflicts -eq 0) { 'rolled-back' } else { 'needs-review' }
                [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
            }
            catch {
                $rollbackException = $_.Exception
                while (($rollbackException -is [System.Management.Automation.MethodInvocationException] -or
                        $rollbackException -is [System.Management.Automation.RuntimeException]) -and
                       $null -ne $rollbackException.InnerException) {
                    $rollbackException = $rollbackException.InnerException
                }
                $rollbackExceptionType = $rollbackException.GetType().Name
                # A failed rollback or final journal write cannot be reported as rolled back.
                $tx.status = 'needs-review'
                try { [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory) }
                catch { }
            }
            $rollbackSummary = if ($null -eq $rollbackExceptionType) { '' }
                else { " rollbackErrorCode=rollback_failed rollbackExceptionType=$rollbackExceptionType." }
            throw "Apply failed; transaction $($tx.id) is $($tx.status). action=$safeActionId stage=$safeStage exceptionType=$originalType errorCode=$errorCode.$rollbackSummary Inspect the private journal."
        }
    }
    finally { $lock.Dispose() }
}

function Invoke-UindosUndo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TransactionId,
          [Parameter(Mandatory)][hashtable]$Adapter,
          [Parameter(Mandatory)][string]$JournalDirectory)
    Assert-UindosAdapter -Adapter $Adapter
    [Guid]$parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($TransactionId, [ref]$parsed)) {
        throw 'Invalid transaction ID.'
    }
    if (-not [IO.Directory]::Exists($JournalDirectory)) { throw 'Journal directory does not exist.' }
    $lock = Enter-UindosJournalLock -Directory $JournalDirectory
    try {
        $filename = Join-Path $JournalDirectory "$($parsed.ToString()).json"
        if (-not [IO.File]::Exists($filename)) { throw 'Transaction journal not found.' }
        $tx = [IO.File]::ReadAllText($filename) | ConvertFrom-Json -Depth 20
        if ($tx.schema -ne 'uindos.transaction/v1' -or $tx.id -ne $parsed.ToString()) {
            throw 'Invalid journal identity/schema.'
        }
        if ($tx.status -in @('undone','rolled-back')) {
            return [pscustomobject]@{ transactionId = $tx.id; status = $tx.status; conflicts = 0 }
        }
        $tx.status = 'undoing'
        [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
        $conflicts = Restore-UindosSteps -Transaction $tx -Adapter $Adapter -Directory $JournalDirectory
        $tx.status = if ($conflicts -eq 0) { 'undone' } else { 'needs-review' }
        [void](Save-UindosJournal -Transaction $tx -Directory $JournalDirectory)
        return [pscustomobject]@{ transactionId = $tx.id; status = $tx.status; conflicts = $conflicts }
    }
    finally { $lock.Dispose() }
}
