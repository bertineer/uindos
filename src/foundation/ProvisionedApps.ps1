# Dedicated privileged provisioning operations for FUTURE Windows user accounts.
# No -AllUsers, no existing-user removal, no servicing/framework/codec targets.
. (Join-Path $PSScriptRoot 'ConsumerApps.ps1')

function Test-UindosProvisionedAppIdentity {
    param([string]$Name, [string]$Version, [string]$PackageName)
    if (@(Get-UindosConsumerAppNames) -cnotcontains $Name -or
        $Version -cnotmatch '^\d+\.\d+\.\d+\.\d+$' -or
        [string]::IsNullOrWhiteSpace($PackageName)) { return $false }

    $publisher = Get-UindosConsumerAppPublisherId -PackageName $Name
    $pattern = '^' + [regex]::Escape($Name) + '_' + [regex]::Escape($Version) +
        '_(?:neutral|x86|x64|arm64)_[A-Za-z0-9.~\-]*_' + [regex]::Escape($publisher) + '$'
    return [bool]($PackageName -cmatch $pattern)
}

function Invoke-UindosProvisioningWindowsPowerShell {
    param([Parameter(Mandatory)][string]$Script)
    # PowerShell 7 DISM has failed with REGDB_E_CLASSNOTREG on Win11 Pro 26H2;
    # verified inbox Windows PowerShell 5.1 does not have this failure.
    $exe = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw 'Windows PowerShell 5.1 is unavailable for package servicing.'
    }
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Script))
    $lines = @(& $exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>$null)
    if ($LASTEXITCODE -ne 0 -or $lines.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$lines[0])) {
        throw 'Windows PowerShell 5.1 provisioning operation failed.'
    }
    return [string]$lines[0]
}

function New-UindosProvisionedAppxProvider {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Provisioning requires Windows.')
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw [System.NotSupportedException]::new('Provisioning preview and apply require Administrator elevation.')
    }
    return @{
        Read = {
            $command = @'
$ErrorActionPreference = 'Stop'
try {
    $packages = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.DisplayName
            version = [string]$_.Version
            packageName = [string]$_.PackageName
        }
    })
    [pscustomobject]@{ schema = 'uindos.provisioned-apps/v1'; packages = $packages } |
        ConvertTo-Json -Depth 5 -Compress
}
catch { exit 1 }
'@
            $json = Invoke-UindosProvisioningWindowsPowerShell -Script $command
            try { $result = ConvertFrom-Json -InputObject $json -ErrorAction Stop }
            catch { throw 'Provisioned package inventory returned malformed JSON.' }
            if ($null -eq $result -or $result.schema -cne 'uindos.provisioned-apps/v1' -or
                $null -eq $result.PSObject.Properties['packages'] -or
                $result.packages -isnot [array]) {
                throw 'Provisioned package inventory returned an invalid envelope.'
            }
            foreach ($row in $result.packages) {
                if ($null -eq $row -or
                    $null -eq $row.PSObject.Properties['name'] -or
                    $null -eq $row.PSObject.Properties['version'] -or
                    $null -eq $row.PSObject.Properties['packageName']) {
                    throw 'Provisioned package inventory returned an invalid record.'
                }
            }
            @($result.packages)
        }
        Remove = {
            param([string]$Name, [string]$Version, [string]$ProvisionedPackageName)
            if (-not (Test-UindosProvisionedAppIdentity -Name $Name -Version $Version -PackageName $ProvisionedPackageName)) {
                throw 'Unsafe provisioning package identity.'
            }
            # Exact identity validated above; accepted alphabet excludes quotes,
            # shell operators and whitespace. The child rechecks before removal.
            $command = @'
$ErrorActionPreference = 'Stop'
try {
    $target = '__PACKAGE_ID__'
    $before = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
        Where-Object { [string]$_.PackageName -ceq $target })
    if ($before.Count -ne 1) { throw 'Provisioned package changed.' }
    [void](Remove-AppxProvisionedPackage -Online -PackageName $target -ErrorAction Stop)
    $after = @(Get-AppxProvisionedPackage -Online -ErrorAction Stop |
        Where-Object { [string]$_.PackageName -ceq $target })
    if ($after.Count -ne 0) { throw 'Provisioned package still present.' }
    [pscustomobject]@{ schema = 'uindos.deprovision-result/v1'; status = 'removed' } |
        ConvertTo-Json -Compress
}
catch { exit 1 }
'@
            $command = $command.Replace('__PACKAGE_ID__', $ProvisionedPackageName)
            $json = Invoke-UindosProvisioningWindowsPowerShell -Script $command
            try { $result = ConvertFrom-Json -InputObject $json -ErrorAction Stop }
            catch { throw 'Provisioning command returned malformed JSON.' }
            if ($null -eq $result -or $result.schema -cne 'uindos.deprovision-result/v1' -or
                $result.status -cne 'removed') {
                throw 'Provisioning command did not confirm removal.'
            }
        }
    }
}

function Assert-UindosProvisionedAppxProvider {
    param([Parameter(Mandatory)][hashtable]$Provider)
    foreach ($method in @('Read','Remove')) {
        if (-not $Provider.ContainsKey($method) -or $Provider[$method] -isnot [scriptblock]) {
            throw "Provisioned AppX provider missing '$method'."
        }
    }
}

function Get-UindosProvisionedAppPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Provider, [AllowNull()]$OsInfo)

    [void](Assert-UindosSupportedAppRemovalOs -OsInfo $OsInfo)
    Assert-UindosProvisionedAppxProvider -Provider $Provider
    # Read ALL provisioned state once. Failure must abort, never become 'absent'.
    $installed = @(& $Provider.Read)
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @(Get-UindosConsumerAppNames)) {
        $matches = @($installed | Where-Object { $null -ne $_ -and [string]$_.name -ceq $name })
        $status = 'absent'
        $reason = 'not-provisioned-for-new-users'
        $version = $null
        $packageName = $null
        if ($matches.Count -gt 1) {
            $status = 'blocked'
            $reason = 'multiple-provisioned-identities'
        }
        elseif ($matches.Count -eq 1) {
            $row = $matches[0]
            $version = [string]$row.version
            $packageName = [string]$row.packageName
            if (-not (Test-UindosProvisionedAppIdentity -Name $name -Version $version -PackageName $packageName)) {
                $status = 'blocked'
                $reason = 'unknown-or-mismatched-provisioned-identity'
            }
            else {
                $status = 'ready'
                $reason = 'curated-new-user-provisioning'
            }
        }
        $entries.Add([pscustomobject]@{
            name = $name
            version = $version
            packageName = $packageName
            status = $status
            reason = $reason
        })
    }
    [pscustomobject]@{
        schema = 'uindos.deprovision-plan/v1'
        mode = 'read-only'
        scope = 'new-users-only'
        noAutomaticRollback = $true
        entries = @($entries.ToArray())
        removalCount = @($entries | Where-Object status -eq 'ready').Count
        blockedCount = @($entries | Where-Object status -eq 'blocked').Count
    }
}

function Invoke-UindosProvisionedAppRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Provider,
        [Parameter(Mandatory)][string]$JournalDirectory,
        [switch]$Apply,
        [switch]$AcceptDeprovisioning,
        [AllowNull()]$OsInfo
    )
    if (-not $Apply -or -not $AcceptDeprovisioning) {
        throw 'Deprovisioning requires BOTH -Apply and -AcceptDeprovisioning.'
    }
    [void](Get-UindosProvisionedAppPlan -Provider $Provider -OsInfo $OsInfo)
    $lock = Enter-UindosJournalLock -Directory $JournalDirectory
    try {
        $plan = Get-UindosProvisionedAppPlan -Provider $Provider -OsInfo $OsInfo
        if ($plan.blockedCount -gt 0) {
            throw 'Unrecognized provisioned package identity; no deprovisioning started.'
        }
        if ($plan.removalCount -eq 0) {
            return [pscustomobject]@{ status='unchanged'; journalId=$null; removed=0; remaining=0 }
        }
        $journal = [pscustomobject]@{
            schema = 'uindos.deprovision/v1'
            id = [Guid]::NewGuid().ToString()
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            scope = 'new-users-only'
            status = 'prepared'
            noAutomaticRollback = $true
            items = @($plan.entries | Where-Object status -eq 'ready' | ForEach-Object {
                [pscustomobject]@{name=$_.name; version=$_.version; packageName=$_.packageName; phase='prepared'}
            })
        }
        [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
        $journal.status = 'removing'
        [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
        foreach ($item in $journal.items) {
            # Re-read before EACH mutation. Stop if another actor updated the image.
            try {
                $current = @(& $Provider.Read | Where-Object { $null -ne $_ -and [string]$_.name -ceq $item.name })
                if ($current.Count -ne 1 -or [string]$current[0].version -cne $item.version -or
                    [string]$current[0].packageName -cne $item.packageName -or
                    -not (Test-UindosProvisionedAppIdentity -Name $item.name -Version $item.version -PackageName $item.packageName)) {
                    throw 'Provisioned package changed before removal.'
                }
                $item.phase = 'removing'
                [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
                & $Provider.Remove $item.name $item.version $item.packageName
                $after = @(& $Provider.Read | Where-Object { $null -ne $_ -and [string]$_.name -ceq $item.name })
                if ($after.Count -ne 0) { throw 'Provisioned package still present after removal.' }
                $item.phase = 'removed'
            }
            catch {
                # Sanitized journal: never persist servicing errors or local paths.
                $item.phase = 'needs-review'
                $journal.status = 'needs-review'
            }
            [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
            if ($journal.status -eq 'needs-review') { break }
        }
        if ($journal.status -ne 'needs-review') { $journal.status = 'completed' }
        [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
        $removed = @($journal.items | Where-Object phase -eq 'removed').Count
        [pscustomobject]@{
            status=$journal.status
            journalId=$journal.id
            removed=$removed
            remaining=($journal.items.Count - $removed)
        }
    }
    finally { $lock.Dispose() }
}
