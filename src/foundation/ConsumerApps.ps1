# Opinionated current-user consumer/media AppX operations. New-user provisioning is separate.
# No frameworks, codecs, servicing APIs or other Windows internals removed.
. (Join-Path $PSScriptRoot '..\core\Transactions.ps1')

function Get-UindosConsumerAppNames {
    # Only these explicit identities are eligible; never wildcard/remove-all.
    return @(
        'Microsoft.Copilot'
        'Microsoft.BingNews'
        'Microsoft.BingWeather'
        'Microsoft.WindowsFeedbackHub'
        'Microsoft.MicrosoftSolitaireCollection'
        'Clipchamp.Clipchamp'
        'Microsoft.ZuneMusic'
        'Microsoft.ZuneVideo'
        'Microsoft.WindowsSoundRecorder'
        'Microsoft.WindowsCamera'
        'Microsoft.Windows.Photos'
        'Microsoft.Paint'
        'Microsoft.MicrosoftOfficeHub'
        'Microsoft.OutlookForWindows'
        'MSTeams'
        'Microsoft.MicrosoftStickyNotes'
        'Microsoft.Todos'
        'Microsoft.PowerAutomateDesktop'
        'Microsoft.Windows.DevHome'
        'Microsoft.YourPhone'
        'Microsoft.WindowsAlarms'
    )
}

function Get-UindosConsumerAppPublisherId {
    param([Parameter(Mandatory)][string]$PackageName)
    if (@(Get-UindosConsumerAppNames) -cnotcontains $PackageName) {
        throw 'Package is outside curated consumer app list.'
    }
    if ($PackageName -ceq 'Clipchamp.Clipchamp') { return 'yxz26nhyzhsrt' }
    return '8wekyb3d8bbwe'
}

function Assert-UindosSupportedAppRemovalOs {
    param([AllowNull()]$OsInfo)
    if ($null -eq $OsInfo) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Windows 11 Pro is required.')
        }
        $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $OsInfo = [pscustomobject]@{
            editionId = [string]$os.EditionID
            build = [string]$os.CurrentBuildNumber
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        }
    }
    [long]$build = 0
    if ([string]$OsInfo.editionId -cnotin @('Professional','ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build,[ref]$build) -or
        $build -lt 22000 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64')) {
        throw [System.NotSupportedException]::new('App removal v1 is limited to Windows 11 Pro/Pro N x64/ARM64.')
    }
    return $true
}

function New-UindosAppxProvider {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('AppX operations require Windows.')
    }
    foreach ($cmd in @('Get-AppxPackage','Remove-AppxPackage')) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw [System.NotSupportedException]::new("Required AppX command '$cmd' is unavailable.")
        }
    }
    return @{
        Read = {
            param([string]$PackageName)
            if (@(Get-UindosConsumerAppNames) -cnotcontains $PackageName) {
                throw 'AppX read outside curated package list.'
            }
            @(Get-AppxPackage -Name $PackageName -ErrorAction Stop |
                Where-Object { $_.Name -ceq $PackageName })
        }
        Remove = {
            param([string]$PackageName, [string]$PackageFullName)
            if (@(Get-UindosConsumerAppNames) -cnotcontains $PackageName) {
                throw 'AppX removal outside curated package list.'
            }
            if (-not (Test-UindosAppxIdentity -PackageName $PackageName -PackageFullName $PackageFullName)) {
                throw 'Unsafe AppX package identity.'
            }
            Remove-AppxPackage -Package $PackageFullName -ErrorAction Stop
        }
    }
}

function Assert-UindosAppxProvider {
    param([Parameter(Mandatory)][hashtable]$Provider)
    foreach ($cmd in @('Read','Remove')) {
        if (-not $Provider.ContainsKey($cmd) -or $Provider[$cmd] -isnot [scriptblock]) {
            throw "AppX provider must implement '$cmd'."
        }
    }
}

function Test-UindosAppxIdentity {
    param([string]$PackageName,[string]$PackageFullName)
    if (@(Get-UindosConsumerAppNames) -cnotcontains $PackageName) { return $false }
    if ([string]::IsNullOrWhiteSpace($PackageFullName)) { return $false }
    $publisher = Get-UindosConsumerAppPublisherId -PackageName $PackageName
    $pattern = '^' + [regex]::Escape($PackageName) + '_[0-9][A-Za-z0-9_.~+-]*__' + [regex]::Escape($publisher) + '$'
    return [bool]($PackageFullName -cmatch $pattern)
}

function Get-UindosConsumerAppPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Provider,[AllowNull()]$OsInfo)

    [void](Assert-UindosSupportedAppRemovalOs -OsInfo $OsInfo)
    Assert-UindosAppxProvider -Provider $Provider
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @(Get-UindosConsumerAppNames)) {
        $packages = @(& $Provider.Read $name)
        # Exact read-match plus bounded count. No wildcard or unknown publisher is removed.
        $state = 'absent'
        $reason = 'not-installed-for-current-user'
        $fullName = $null
        $version = $null
        if ($packages.Count -gt 1) {
            $state = 'blocked'
            $reason = 'multiple-identities-require-review'
        }
        elseif ($packages.Count -eq 1) {
            $package = $packages[0]
            $fullName = [string]$package.PackageFullName
            $version = [string]$package.Version
            if ([string]$package.Name -cne $name -or
                [string]$package.PublisherId -cne (Get-UindosConsumerAppPublisherId -PackageName $name) -or
                -not (Test-UindosAppxIdentity -PackageName $name -PackageFullName $fullName)) {
                $state = 'blocked'
                $reason = 'identity-or-publisher-not-recognized'
            }
            elseif ($package.IsFramework -or $package.IsResourcePackage -or $package.NonRemovable) {
                $state = 'blocked'
                $reason = 'framework-resource-or-protected'
            }
            else {
                $state = 'ready'
                $reason = 'curated-current-user-app'
            }
        }
        $entries.Add([pscustomobject]@{
            name = $name
            version = $version
            packageFullName = $fullName
            status = $state
            reason = $reason
        })
    }
    return [pscustomobject]@{
        schema = 'uindos.app-removal-plan/v1'
        scope = 'current-user-only'
        mode = 'read-only'
        noAutomaticRollback = $true
        entries = @($entries.ToArray())
        removalCount = @($entries | Where-Object { $_.status -eq 'ready' }).Count
        blockedCount = @($entries | Where-Object { $_.status -eq 'blocked' }).Count
    }
}

function Invoke-UindosConsumerAppRemoval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Provider,
        [Parameter(Mandatory)][string]$JournalDirectory,
        [switch]$Apply,
        [switch]$AcceptAppDataLoss,
        [AllowNull()]$OsInfo
    )
    if (-not $Apply -or -not $AcceptAppDataLoss) {
        throw 'Removal requires BOTH -Apply and -AcceptAppDataLoss. Preview is the default.'
    }
    # The initial preflight is read-only; the later one is repeated under lock.
    [void](Get-UindosConsumerAppPlan -Provider $Provider -OsInfo $OsInfo)
    $lock = Enter-UindosJournalLock -Directory $JournalDirectory
    try {
        $plan = Get-UindosConsumerAppPlan -Provider $Provider -OsInfo $OsInfo
        if ($plan.blockedCount -gt 0) {
            throw 'Unsafe or unrecognized AppX identity detected; no packages removed.'
        }
        if ($plan.removalCount -eq 0) {
            return [pscustomobject]@{
                status = 'unchanged'; journalId = $null; removed = 0; remaining = 0
            }
        }
        $journal = [pscustomobject]@{
            schema = 'uindos.app-removal/v1'
            id = [Guid]::NewGuid().ToString()
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            scope = 'current-user-only'
            noAutomaticRollback = $true
            status = 'prepared'
            items = @($plan.entries | Where-Object { $_.status -eq 'ready' } | ForEach-Object {
                [pscustomobject]@{
                    name = $_.name
                    packageFullName = $_.packageFullName
                    phase = 'prepared'
                }
            })
        }
        [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
        $journal.status = 'removing'
        [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
        foreach ($item in $journal.items) {
            # External update/reinstallation after planning is a stop, not a force-remove.
            $current = @(& $Provider.Read $item.name)
            if ($current.Count -ne 1 -or
                [string]$current[0].PackageFullName -cne $item.packageFullName -or
                [string]$current[0].PublisherId -cne (Get-UindosConsumerAppPublisherId -PackageName $item.name) -or
                $current[0].IsFramework -or $current[0].IsResourcePackage -or
                $current[0].NonRemovable) {
                $item.phase = 'needs-review'
                $journal.status = 'needs-review'
                [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
                break
            }
            $item.phase = 'removing'
            [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
            try {
                & $Provider.Remove $item.name $item.packageFullName
                $after = @(& $Provider.Read $item.name |
                    Where-Object { [string]$_.PackageFullName -ceq $item.packageFullName })
                if ($after.Count -ne 0) { throw 'Package still installed after removal.' }
                $item.phase = 'removed'
            }
            catch {
                # Raw error messages could contain profile paths; do not put them in journal.
                $item.phase = 'needs-review'
                $journal.status = 'needs-review'
            }
            [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
            if ($journal.status -eq 'needs-review') { break }
        }
        if ($journal.status -ne 'needs-review') { $journal.status = 'completed' }
        [void](Save-UindosJournal -Transaction $journal -Directory $JournalDirectory)
        $removedCount = @($journal.items | Where-Object { $_.phase -eq 'removed' }).Count
        return [pscustomobject]@{
            status = $journal.status
            journalId = $journal.id
            removed = $removedCount
            remaining = $journal.items.Count - $removedCount
        }
    }
    finally { $lock.Dispose() }
}
