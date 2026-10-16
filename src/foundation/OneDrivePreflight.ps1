# Read-only OneDrive Win32 preflight. Never returns paths, account identifiers,
# registry command strings, names, or file contents.

function Assert-UindosSupportedOneDrivePreflightOs {
    param([Parameter(Mandatory)][object]$OsInfo)
    [long]$build = 0
    if ([string]$OsInfo.editionId -cnotin @('Professional', 'ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build, [ref]$build) -or
        [string]$OsInfo.architecture -cnotin @('X64', 'Arm64') -or
        $build -lt 22000) {
        throw [System.NotSupportedException]::new(
            'OneDrive preflight v1 targets Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later.'
        )
    }
}

function Get-UindosOneDriveDefaultProviders {
    return [ordered]@{
        os = { Get-UindosOneDriveOsInfo }
        machine64 = { Get-UindosOneDriveUninstallEntries -Hive LocalMachine -RegistryView Registry64 -Scope machine64 }
        machine32 = { Get-UindosOneDriveUninstallEntries -Hive LocalMachine -RegistryView Registry32 -Scope machine32 }
        currentUser = { Get-UindosOneDriveUninstallEntries -Hive CurrentUser -RegistryView Registry64 -Scope currentUser }
        process = { [pscustomobject]@{ running = (@(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -ceq 'OneDrive' }).Count -gt 0) } }
        accounts = { Get-UindosOneDriveAccountObservation }
        knownFolders = { Get-UindosOneDriveKnownFolderPaths }
    }
}

function Get-UindosOneDriveOsInfo {
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    [pscustomobject]@{
        editionId = [string]$os.EditionID
        build = [string]$os.CurrentBuildNumber
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
}

function Get-UindosOneDriveUninstallEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Microsoft.Win32.RegistryHive]$Hive,
        [Parameter(Mandatory)][Microsoft.Win32.RegistryView]$RegistryView,
        [Parameter(Mandatory)][string]$Scope
    )
    $base = $null
    $uninstall = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $RegistryView)
        $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', $false)
        if ($null -eq $uninstall) { return [pscustomobject]@{ entries = [object[]]@() } }
        $rows = foreach ($subkeyName in $uninstall.GetSubKeyNames()) {
            $app = $null
            try {
                $app = $uninstall.OpenSubKey($subkeyName, $false)
                if ($null -eq $app) { continue }
                $displayName = [string]$app.GetValue('DisplayName', '')
                if ($displayName -cne 'Microsoft OneDrive') { continue }
                $publisher = [string]$app.GetValue('Publisher', '')
                $raw = [pscustomobject]@{ displayName=$displayName; publisher=$publisher }
                if ($publisher -ceq 'Microsoft Corporation') {
                    $raw | Add-Member -NotePropertyName uninstallString -NotePropertyValue ([string]$app.GetValue('UninstallString', ''))
                    $raw | Add-Member -NotePropertyName quietUninstallString -NotePropertyValue ([string]$app.GetValue('QuietUninstallString', ''))
                }
                ConvertTo-UindosOneDriveRegistrationObservation -Entry $raw -Scope $Scope
            }
            finally { if ($null -ne $app) { $app.Dispose() } }
        }
        [pscustomobject]@{ entries = [object[]]@($rows) }
    }
    finally {
        if ($null -ne $uninstall) { $uninstall.Dispose() }
        if ($null -ne $base) { $base.Dispose() }
    }
}

function ConvertTo-UindosOneDriveRegistrationObservation {
    param([Parameter(Mandatory)][object]$Entry, [Parameter(Mandatory)][string]$Scope)
    if ([string]$Entry.displayName -cne 'Microsoft OneDrive') { return $null }
    if ([string]$Entry.publisher -cne 'Microsoft Corporation') {
        return [pscustomobject]@{
            scope = $Scope
            matchesExpectedMetadata = $false
            identityReviewRequired = $true
            uninstallCommandPresent = $false
            uninstallCommandSources = @()
        }
    }
    $sources = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.uninstallString)) { $sources += 'UninstallString' }
    if (-not [string]::IsNullOrWhiteSpace([string]$Entry.quietUninstallString)) { $sources += 'QuietUninstallString' }
    [pscustomobject]@{
        scope = $Scope
        matchesExpectedMetadata = $true
        identityReviewRequired = $false
        uninstallCommandPresent = ($sources.Count -gt 0)
        uninstallCommandSources = $sources
    }
}

function Get-UindosOneDriveAccountObservation {
    $base = $null
    $accounts = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::CurrentUser,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $accounts = $base.OpenSubKey('Software\Microsoft\OneDrive\Accounts', $false)
        if ($null -eq $accounts) { return [pscustomobject]@{ configured = $false; roots = [string[]]@() } }
        $accountNames = @($accounts.GetSubKeyNames())
        $roots = @(
            foreach ($accountName in $accountNames) {
                $account = $null
                try {
                    $account = $accounts.OpenSubKey($accountName, $false)
                    if ($null -eq $account -or @($account.GetValueNames()) -cnotcontains 'UserFolder') { continue }
                    $userFolder = [string]$account.GetValue('UserFolder', '')
                    if (-not [string]::IsNullOrWhiteSpace($userFolder)) { $userFolder }
                }
                finally { if ($null -ne $account) { $account.Dispose() } }
            }
        )
        [pscustomobject]@{ configured = ($accountNames.Count -gt 0); roots = [string[]]@($roots) }
    }
    finally {
        if ($null -ne $accounts) { $accounts.Dispose() }
        if ($null -ne $base) { $base.Dispose() }
    }
}

function Get-UindosOneDriveKnownFolderPaths {
    # Metadata only: do not verify or create redirected/network directories.
    $option = [Environment+SpecialFolderOption]::DoNotVerify
    [pscustomobject]@{
        desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory,$option)
        documents = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments,$option)
        pictures = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyPictures,$option)
    }
}

function Invoke-UindosOneDriveProbe {
    param([Parameter(Mandatory)][string]$Name, [AllowNull()][scriptblock]$Provider)
    if ($null -eq $Provider) {
        return [pscustomobject]@{ status = 'not-collected'; data = $null }
    }
    try {
        [pscustomobject]@{ status = 'ok'; data = (& $Provider) }
    }
    catch [System.NotSupportedException] {
        [pscustomobject]@{ status = 'unsupported'; data = $null }
    }
    catch [System.UnauthorizedAccessException] {
        [pscustomobject]@{ status = 'access-denied'; data = $null }
    }
    catch [System.Security.SecurityException] {
        [pscustomobject]@{ status = 'access-denied'; data = $null }
    }
    catch {
        # Exceptions may contain account names, registry paths, or file paths.
        [pscustomobject]@{ status = 'error'; data = $null }
    }
}

function Test-UindosOneDrivePathWithinRoot {
    param([AllowNull()][string]$Path, [AllowEmptyCollection()][string[]]$Roots = @())
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    foreach ($root in $Roots) {
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        $normalizedRoot = [Environment]::ExpandEnvironmentVariables($root).TrimEnd('\', '/')
        $normalizedPath = [Environment]::ExpandEnvironmentVariables($Path)
        if ($normalizedPath.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $normalizedPath.StartsWith($normalizedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $normalizedPath.StartsWith($normalizedRoot + '/', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-UindosOneDrivePreflight {
    [CmdletBinding()]
    param([AllowNull()][System.Collections.IDictionary]$Providers)

    $mockMode = $PSBoundParameters.ContainsKey('Providers')
    if (-not $mockMode) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('OneDrive preflight requires Windows unless test providers are injected.')
        }
        $Providers = Get-UindosOneDriveDefaultProviders
    }
    $names = @('os', 'machine64', 'machine32', 'currentUser', 'process', 'accounts', 'knownFolders')
    $probes = [ordered]@{}
    foreach ($name in $names) {
        $provider = $null
        if ($null -ne $Providers -and $Providers.Contains($name)) { $provider = $Providers[$name] }
        $probes[$name] = Invoke-UindosOneDriveProbe -Name $name -Provider $provider
    }

    foreach ($source in @('machine64', 'machine32', 'currentUser')) {
        if ($probes[$source].status -ne 'ok') { continue }
        $records = $probes[$source].data
        if ($null -eq $records -or $null -eq $records.PSObject.Properties['entries'] -or
            $records.entries -isnot [array]) {
            $probes[$source] = [pscustomobject]@{ status='error'; data=$null }
        }
    }

    $platformStatus = 'unknown'
    if ($probes.os.status -eq 'ok') {
        try { Assert-UindosSupportedOneDrivePreflightOs -OsInfo $probes.os.data; $platformStatus = 'supported' }
        catch [System.NotSupportedException] { $platformStatus = 'unsupported' }
        catch { $platformStatus = 'error' }
    }

    $sourceNames = @('machine64', 'machine32', 'currentUser')
    $completedSources = @($sourceNames | Where-Object { $probes[$_].status -eq 'ok' }).Count
    $failedSources = @($sourceNames | Where-Object { $probes[$_].status -eq 'error' }).Count
    $matched = @(
        foreach ($source in $sourceNames) {
            if ($probes[$source].status -ne 'ok') { continue }
            foreach ($entry in @($probes[$source].data.entries)) {
                if ($entry.matchesExpectedMetadata -eq $true) { $entry }
            }
        }
    )
    $identityReviewRequired = $false
    foreach ($source in $sourceNames) {
        if ($probes[$source].status -ne 'ok') { continue }
        foreach ($entry in @($probes[$source].data.entries)) {
            if ($entry.identityReviewRequired -eq $true) { $identityReviewRequired = $true }
        }
    }
    $collectionStatus = if ($completedSources -eq $sourceNames.Count) { 'complete' } elseif ($completedSources -gt 0) { 'partial' } elseif ($failedSources -gt 0) { 'error' } else { 'unknown' }
    $installationStatus = if ($matched.Count -gt 0) { 'present' } elseif ($collectionStatus -eq 'complete') { 'absent' } elseif ($collectionStatus -eq 'error') { 'error' } else { 'unknown' }

    $registrations = @(
        foreach ($entry in $matched) {
            [pscustomobject]@{
                scope = [string]$entry.scope
                uninstallCommandPresent = [bool]$entry.uninstallCommandPresent
                uninstallCommandSources = @($entry.uninstallCommandSources)
                uninstallCommandProvenance = 'uninstall-registry-entry'
            }
        }
    )

    $account = $probes.accounts
    $accountStatus = if ($account.status -eq 'ok') { if ($account.data.configured) { 'present' } else { 'not-observed' } } else { 'unknown' }
    $processStatus = if ($probes.process.status -eq 'ok') { if ($probes.process.data.running) { 'running' } else { 'not-running' } } else { 'unknown' }
    $probeStatus = [ordered]@{}
    foreach ($name in $names) { $probeStatus[$name] = $probes[$name].status }
    $knownFolders = [ordered]@{}
    foreach ($folder in @('desktop', 'documents', 'pictures')) {
        $folderPath = if ($probes.knownFolders.status -eq 'ok') { [string]$probes.knownFolders.data.$folder } else { '' }
        $knownFolders[$folder] = if ([string]::IsNullOrWhiteSpace($folderPath) -or
            $probes.knownFolders.status -ne 'ok' -or $account.status -ne 'ok' -or
            @($account.data.roots).Count -eq 0) {
            [pscustomobject]@{ status = 'unknown'; redirectedToDetectedOneDriveRoot = $null }
        } else {
            $redirected = Test-UindosOneDrivePathWithinRoot -Path $folderPath -Roots @($account.data.roots)
            [pscustomobject]@{ status = if ($redirected) { 'detected' } else { 'not-detected' }; redirectedToDetectedOneDriveRoot = [bool]$redirected }
        }
    }

    [pscustomobject]@{
        schema = 'uindos.onedrive-preflight/v1'
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        collection = if ($mockMode) { 'injected-test-providers' } else { 'local-windows-read-only' }
        probeStatus = [pscustomobject]$probeStatus
        platform = [pscustomobject]@{ status = $platformStatus }
        installation = [pscustomobject]@{
            status = $installationStatus
            registryCollection = $collectionStatus
            matchingRegistrationCount = $matched.Count
            identityReviewRequired = $identityReviewRequired
            registrations = $registrations
        }
        process = [pscustomobject]@{ status = $processStatus; running = if ($processStatus -eq 'unknown') { $null } else { $processStatus -eq 'running' } }
        currentUserAccount = [pscustomobject]@{ registryMetadata = $accountStatus; signInStatus = 'unknown' }
        knownFolders = [pscustomobject]$knownFolders
        filesOnDemand = [pscustomobject]@{ status = 'unknown'; requiresManualReview = $true; hydrationStatus = 'unknown' }
        assessment = [pscustomobject]@{
            uninstallReadiness = 'manual-review-required'
            safeToUninstall = $false
            note = 'This preflight does not establish active sync state, cloud backup completeness, or local hydration.'
        }
    }
}
