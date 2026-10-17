# Read-only Start pin preflight. It reports only fixed target identities and counts.

function ConvertTo-UindosStartPinsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Layout,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PackageFamilies
    )

    if ($null -eq $Layout -or $null -eq $Layout.PSObject.Properties['pinnedList'] -or
        $Layout.pinnedList -isnot [array]) {
        throw [System.IO.InvalidDataException]::new('Start layout must contain a pinnedList array.')
    }

    $knownPins = @(
        [pscustomobject]@{ label='WhatsApp'; identity='5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App'; family='5319275A.WhatsAppDesktop_cv1g1gvanyjgm' }
        [pscustomobject]@{ label='LinkedIn'; identity='7EE7776C.LinkedInforWindows_w1wdnht996qgy!App'; family='7EE7776C.LinkedInforWindows_w1wdnht996qgy' }
    )
    $registered = @{}
    foreach ($family in $PackageFamilies) {
        if ($family -isnot [string] -or [string]::IsNullOrWhiteSpace($family)) {
            throw [System.IO.InvalidDataException]::new('Package family inventory is malformed.')
        }
        foreach ($target in $knownPins) {
            if ([string]::Equals($family,$target.family,[StringComparison]::OrdinalIgnoreCase)) { $registered[$target.family] = $true }
        }
    }

    $counts = [ordered]@{ packagedAppId=0; desktopAppLink=0; desktopAppId=0 }
    $matched = @{}
    foreach ($pin in $Layout.pinnedList) {
        if ($null -eq $pin) { throw [System.IO.InvalidDataException]::new('Start pin entry is malformed.') }
        $propertyNames = @($pin.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' } | ForEach-Object { $_.Name })
        if (@($propertyNames | Where-Object { $_ -cnotin @('packagedAppId','desktopAppLink','desktopAppId') }).Count -gt 0) {
            throw [System.IO.InvalidDataException]::new('Start pin contains an unsupported identifier type.')
        }
        $present = @(@('packagedAppId','desktopAppLink','desktopAppId') | Where-Object { $null -ne $pin.PSObject.Properties[$_] })
        if ($present.Count -ne 1) { throw [System.IO.InvalidDataException]::new('Start pin must contain exactly one supported identifier.') }
        $type = [string]$present[0]
        $identity = $pin.PSObject.Properties[$type].Value
        if ($identity -isnot [string] -or [string]::IsNullOrWhiteSpace($identity)) {
            throw [System.IO.InvalidDataException]::new('Start pin identifier must be a non-empty string.')
        }
        $counts[$type]++
        foreach ($target in $knownPins) {
            if ($type -eq 'packagedAppId' -and [string]::Equals($identity,$target.identity,[StringComparison]::OrdinalIgnoreCase)) { $matched[$target.family] = $true }
        }
    }

    [pscustomobject]@{
        schema = 'uindos.start-pins-preflight/v1'
        startPinCount = $Layout.pinnedList.Count
        countsByType = [pscustomobject]$counts
        targets = @(
            foreach ($target in $knownPins) {
                [pscustomobject]@{
                    label = $target.label
                    identity = $target.identity
                    pinned = [bool]$matched.ContainsKey($target.family)
                    currentUserPackageRegistered = [bool]$registered.ContainsKey($target.family)
                }
            }
        )
        assessment = 'manual-review-required'
        limitations = @(
            'This export is evidence of current pins and is not an exact undo record.'
            'A pin does not establish whether its application is installed.'
            'Package registration is checked only for the current user by exact package family.'
        )
    }
}

function Get-UindosStartPinsPreflight {
    [CmdletBinding()]
    param(
        [Parameter()][object]$OsInfo,
        [Parameter()][string]$PrivateExportDirectory
    )

    $windows = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)
    if (-not $windows -and $null -eq $OsInfo) {
        throw [System.NotSupportedException]::new('Start pin preflight requires Windows.')
    }
    if ($null -eq $OsInfo) {
        $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $OsInfo = [pscustomobject]@{
            editionId=[string]$os.EditionID
            build=[string]$os.CurrentBuildNumber
            architecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        }
    }
    [long]$build = 0
    if ([string]$OsInfo.editionId -cnotin @('Professional','ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build,[ref]$build) -or $build -lt 22000 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64')) {
        throw [System.NotSupportedException]::new('Start pin preflight targets Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later.')
    }
    if (-not $windows) { throw [System.NotSupportedException]::new('Native Start pin collection requires Windows.') }

    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { throw [InvalidOperationException]::new('Local application data directory is unavailable.') }
    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $localAppData 'uindos\start-pins-preflight')).TrimEnd('\')
    $preserve = -not [string]::IsNullOrWhiteSpace($PrivateExportDirectory)
    if ($preserve) {
        if (-not [IO.Path]::IsPathRooted($PrivateExportDirectory)) { throw [ArgumentException]::new('Private export directory must be an absolute path.') }
        $artifactDirectory = [IO.Path]::GetFullPath($PrivateExportDirectory).TrimEnd('\','/')
        $pathRoot = [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($PrivateExportDirectory)).TrimEnd('\','/')
        if ($artifactDirectory.Length -eq 0 -or [string]::Equals($artifactDirectory,$pathRoot,[StringComparison]::OrdinalIgnoreCase)) {
            throw [ArgumentException]::new('Private export directory must name a new directory, not a filesystem root.')
        }
        if ([IO.Directory]::Exists($artifactDirectory) -or [IO.File]::Exists($artifactDirectory)) {
            throw [IO.IOException]::new('Private export directory already exists; refusing to overwrite it.')
        }
    } else {
        $artifactDirectory = Join-Path $allowedRoot ([Guid]::NewGuid().ToString('D'))
    }
    [IO.Directory]::CreateDirectory($artifactDirectory) | Out-Null
    $layoutPath = Join-Path $artifactDirectory 'layout.json'
    $familiesPath = Join-Path $artifactDirectory 'families.json'
    $helperPath = Join-Path $PSScriptRoot 'ExportStartPins.ps1'
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $completed = $false
    try {
        $arguments = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"{0}"' -f $helperPath),'-ArtifactDirectory',('"{0}"' -f $artifactDirectory))
        $process = Start-Process -FilePath $powershell -ArgumentList $arguments -PassThru -WindowStyle Hidden
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            if (-not $process.WaitForExit(5000)) { throw [TimeoutException]::new('Export helper did not stop after timeout.') }
            throw [TimeoutException]::new('Windows PowerShell Start pin export helper timed out.')
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $layoutPath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $familiesPath -PathType Leaf)) {
            throw [InvalidOperationException]::new('Windows PowerShell Start pin export helper failed or returned incomplete evidence.')
        }
        $layout = Get-Content -LiteralPath $layoutPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $familiesDocument = Get-Content -LiteralPath $familiesPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $familiesDocument -or $null -eq $familiesDocument.packageFamilies -or
            $familiesDocument.packageFamilies -isnot [array] -or $null -eq $familiesDocument.context -or
            $familiesDocument.context.elevated -isnot [bool] -or $familiesDocument.context.elevated -ne $false -or
            $familiesDocument.context.sameUserAsExplorer -isnot [bool] -or $familiesDocument.context.sameUserAsExplorer -ne $true) {
            throw [IO.InvalidDataException]::new('Current-user package family evidence is malformed.')
        }
        $report = ConvertTo-UindosStartPinsReport -Layout $layout -PackageFamilies $familiesDocument.packageFamilies
        $report | Add-Member -NotePropertyName collection -NotePropertyValue 'local-windows-read-only'
        $report | Add-Member -NotePropertyName platform -NotePropertyValue ([pscustomobject]@{
            edition = [string]$OsInfo.editionId; build = $build; architecture = [string]$OsInfo.architecture
        })
        $report | Add-Member -NotePropertyName collectorContext -NotePropertyValue ([pscustomobject]@{
            elevated = $false; sameUserAsExplorer = $true
        })
        $completed = $true
        [pscustomobject]@{
            report = $report
            evidence = [pscustomobject]@{ preserved = [bool]$preserve; files = if ($preserve) { @('layout.json','families.json') } else { @() } }
        }
    }
    catch {
        throw [InvalidOperationException]::new('Start pin preflight failed while collecting or validating local evidence.')
    }
    finally {
        if (-not $preserve) {
            # Validate the absolute allowlisted root and our GUID leaf before deleting any artifact.
            if ([IO.Directory]::Exists($artifactDirectory)) {
                $full = [IO.Path]::GetFullPath($artifactDirectory)
                $leaf = [IO.Path]::GetFileName($full)
                $parent = [IO.Path]::GetDirectoryName($full).TrimEnd('\')
                $guid = [Guid]::Empty
                $validTempDirectory = [IO.Path]::IsPathRooted($full) -and
                    [string]::Equals($parent,$allowedRoot,[StringComparison]::OrdinalIgnoreCase) -and
                    [Guid]::TryParseExact($leaf,'D',[ref]$guid) -and $guid.ToString('D') -ceq $leaf
                if (-not $validTempDirectory) { throw [InvalidOperationException]::new('Temporary artifact directory failed its cleanup guard.') }
                foreach ($path in @($layoutPath,$familiesPath)) {
                    $fullArtifact = [IO.Path]::GetFullPath($path)
                    if ([string]::Equals([IO.Path]::GetDirectoryName($fullArtifact).TrimEnd('\'),$full,[StringComparison]::OrdinalIgnoreCase) -and
                        [IO.Path]::GetFileName($fullArtifact) -cin @('layout.json','families.json') -and
                        (Test-Path -LiteralPath $fullArtifact -PathType Leaf)) { [IO.File]::Delete($fullArtifact) }
                }
                if (@(Get-ChildItem -LiteralPath $full -Force).Count -eq 0) { [IO.Directory]::Delete($full,$false) }
            }
        } elseif (-not $completed) {
            # Evidence mode retains failed artifacts for private diagnosis and reports the failure.
        }
    }
}
