# Read-only Windows collectors for the uindos baseline.
# All returned objects intentionally omit device identifiers, account names,
# recovery secrets, IP addresses, package installation paths and file contents.

function Assert-UindosCommand {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw [System.NotSupportedException]::new("Required command '$Name' is unavailable.")
    }
}

function Test-UindosAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-UindosAdministrator {
    if (-not (Test-UindosAdministrator)) {
        throw [System.NotSupportedException]::new('This read-only probe requires an elevated PowerShell session. Other probes still run normally.')
    }
}

function Get-UindosRegistrySetting {
    param([Parameter(Mandatory)][string]$Id,
          [Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Name)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
        return [pscustomobject]@{ id = $Id; configured = $false; value = $null }
    }
    $data = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    $prop = $data.PSObject.Properties[$Name]
    return [pscustomobject]@{
        id = $Id
        configured = ($null -ne $prop)
        value = if ($null -ne $prop) { $prop.Value } else { $null }
    }
}

function Get-UindosOsInfo {
    $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    return [pscustomobject]@{
        editionId = [string]$os.EditionID
        displayVersion = [string]$os.DisplayVersion
        build = [string]$os.CurrentBuildNumber
        updateBuildRevision = $os.UBR
        installationType = [string]$os.InstallationType
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
}

function Get-UindosAppxCurrentUser {
    Assert-UindosCommand 'Get-AppxPackage'
    @(Get-AppxPackage -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Name
            version = [string]$_.Version
            framework = [bool]$_.IsFramework
            nonRemovable = [bool]$_.NonRemovable
        }
    } | Sort-Object name, version)
}

function Get-UindosAppxAllUsers {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Get-AppxPackage'
    @(Get-AppxPackage -AllUsers -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.Name
            version = [string]$_.Version
            framework = [bool]$_.IsFramework
            nonRemovable = [bool]$_.NonRemovable
        }
    } | Sort-Object name, version -Unique)
}

# Windows PowerShell 5.1 hosts DISM cmdlets natively. On certain Windows 11
# builds the imported DISM command can fail in pwsh 7 with REGDB_E_CLASSNOTREG
# (0x80040154) even though the 5.1 and dism.exe paths work.
function Test-UindosProvisionedAppxRegistrationFailure {
    param([Parameter(Mandatory)][System.Exception]$Exception)
    while ($null -ne $Exception) {
        if ($Exception.HResult -eq -2147221164) { return $true }
        $Exception = $Exception.InnerException
    }
    return $false
}

function ConvertTo-UindosProvisionedAppxRows {
    param([AllowEmptyCollection()][object[]]$Packages = @())

    $rows = @(
        foreach ($package in $Packages) {
            if ($null -eq $package) {
                throw [System.IO.InvalidDataException]::new('Provisioned AppX record was null.')
            }
            $nameProperty = $package.PSObject.Properties['DisplayName']
            if ($null -eq $nameProperty) { $nameProperty = $package.PSObject.Properties['name'] }
            $versionProperty = $package.PSObject.Properties['version']
            if ($null -eq $nameProperty -or $null -eq $versionProperty) {
                throw [System.IO.InvalidDataException]::new('Provisioned AppX record fields missing.')
            }
            $name = [string]$nameProperty.Value
            $version = [string]$versionProperty.Value
            if ($name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
                $version -cnotmatch '^\d+\.\d+\.\d+\.\d+$') {
                throw [System.IO.InvalidDataException]::new('Provisioned AppX record has invalid identity or version.')
            }
            [pscustomobject]@{ name = $name; version = $version }
        }
    )
    @($rows | Sort-Object name, version -Unique)
}

function ConvertFrom-UindosProvisionedAppxJson {
    param([Parameter(Mandatory)][string]$Json)

    try {
        $result = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    }
    catch {
        throw [System.IO.InvalidDataException]::new('Windows PowerShell returned invalid provisioning JSON.')
    }
    if ($null -eq $result -or $result.schema -cne 'uindos.provisioned-appx/v1' -or
        $null -eq $result.PSObject.Properties['packages'] -or
        $null -eq $result.packages -or $result.packages -isnot [array]) {
        throw [System.IO.InvalidDataException]::new('Windows PowerShell returned an invalid provisioning envelope.')
    }
    @(ConvertTo-UindosProvisionedAppxRows -Packages @($result.packages))
}

function Invoke-UindosProvisionedAppxWindowsPowerShell {
    # Fixed Windows system executable; never use PATH resolution.
    $exe = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw [System.NotSupportedException]::new('Windows PowerShell 5.1 is unavailable for the DISM compatibility fallback.')
    }
    # EncodedCommand avoids interpolation/quoting and passes no sensitive input.
    # The child emits ONLY compact schema-tagged JSON; no disk file is written.
    $command = @'
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
try {
    $packages = @(
        Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ name = [string]$_.DisplayName; version = [string]$_.Version }
        }
    )
    [pscustomobject]@{ schema = 'uindos.provisioned-appx/v1'; packages = $packages } |
        ConvertTo-Json -Depth 4 -Compress
}
catch {
    [Console]::Error.WriteLine('Provisioned AppX inventory failed in Windows PowerShell.')
    exit 1
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $output = @(& $exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$output[0])) {
        throw [System.InvalidOperationException]::new('Windows PowerShell 5.1 provisioning fallback failed.')
    }
    @(ConvertFrom-UindosProvisionedAppxJson -Json ([string]$output[0]))
}

function Get-UindosProvisionedAppx {
    [CmdletBinding()]
    param(
        [scriptblock]$PrimaryReader,
        [scriptblock]$FallbackReader,
        [switch]$SkipPlatformChecks
    )

    # The override parameters permit isolated mock tests without Windows APIs.
    if (-not $SkipPlatformChecks) {
        Assert-UindosAdministrator
        Assert-UindosCommand 'Get-AppxProvisionedPackage'
    }
    elseif ($null -eq $PrimaryReader -or $null -eq $FallbackReader) {
        throw [System.ArgumentException]::new('Mock mode requires both readers.')
    }

    if ($null -eq $PrimaryReader) {
        $PrimaryReader = { Get-AppxProvisionedPackage -Online -ErrorAction Stop }
    }
    if ($null -eq $FallbackReader) {
        $FallbackReader = { Invoke-UindosProvisionedAppxWindowsPowerShell }
    }
    try {
        $packages = @(& $PrimaryReader)
    }
    catch {
        if (-not (Test-UindosProvisionedAppxRegistrationFailure -Exception $_.Exception)) {
            throw
        }
        $packages = @(& $FallbackReader)
    }
    @(ConvertTo-UindosProvisionedAppxRows -Packages $packages)
}

function Get-UindosWin32Programs {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $apps = foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { continue }
            [pscustomobject]@{
                name = [string]$item.DisplayName
                version = [string]$item.DisplayVersion
                publisher = [string]$item.Publisher
            }
        }
    }
    @($apps | Sort-Object name, version, publisher -Unique)
}

function Get-UindosPrivacyPolicies {
    $settings = @(
        @('diagnostics.allowTelemetry.policy', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry'),
        @('diagnostics.allowTelemetry.legacy', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection', 'AllowTelemetry'),
        @('consumer.disableConsumerFeatures', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'DisableWindowsConsumerFeatures'),
        @('copilot.turnOffLegacyCopilot', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot'),
        @('advertising.currentUser', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled'),
        @('privacy.tailoredExperiences.currentUser', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled'),
        @('security.smartScreenExplorer', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer', 'SmartScreenEnabled'),
        @('security.smartScreenPolicy', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableSmartScreen'),
        @('security.uac', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA'),
        @('updates.useWsus', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'UseWUServer'),
        @('updates.noAutoUpdate', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'NoAutoUpdate'),
        @('updates.wsusServerPresent', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'WUServer')
    )
    foreach ($entry in $settings) {
        $setting = Get-UindosRegistrySetting -Id $entry[0] -Path $entry[1] -Name $entry[2]
        if ($setting.id -eq 'updates.wsusServerPresent') {
            # Do not publish internal organization URLs or network addresses.
            $setting.value = $null
        }
        $setting
    }
}

function Get-UindosServiceStatus {
    foreach ($name in @('wuauserv', 'BITS', 'UsoSvc', 'WaaSMedicSvc', 'WinDefend', 'MpsSvc', 'DiagTrack')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        [pscustomobject]@{
            name = $name
            installed = ($null -ne $service)
            status = if ($service) { [string]$service.Status } else { $null }
            startType = if ($service) { [string]$service.StartType } else { $null }
        }
    }
}

function Get-UindosDefenderStatus {
    Assert-UindosCommand 'Get-MpComputerStatus'
    $d = Get-MpComputerStatus -ErrorAction Stop
    [pscustomobject]@{
        antivirusEnabled = $d.AntivirusEnabled
        realTimeProtectionEnabled = $d.RealTimeProtectionEnabled
        tamperProtected = $d.IsTamperProtected
        signatureVersion = [string]$d.AntivirusSignatureVersion
    }
}

function Get-UindosFirewallStatus {
    Assert-UindosCommand 'Get-NetFirewallProfile'
    @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{ profile = [string]$_.Name; enabled = [bool]$_.Enabled }
    } | Sort-Object profile)
}

function Get-UindosBitLockerStatus {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Get-BitLockerVolume'
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    [pscustomobject]@{
        volumeType = [string]$volume.VolumeType
        protectionStatus = [string]$volume.ProtectionStatus
        volumeStatus = [string]$volume.VolumeStatus
        encryptionPercentage = $volume.EncryptionPercentage
    }
}

function Get-UindosSecureBootStatus {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Confirm-SecureBootUEFI'
    [pscustomobject]@{ enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) }
}

function Get-UindosSystemDisk {
    $drive = [System.IO.DriveInfo]::new("$($env:SystemDrive)\")
    if (-not $drive.IsReady) { throw 'System volume not ready.' }
    [pscustomobject]@{
        sizeBytes = [int64]$drive.TotalSize
        freeBytes = [int64]$drive.AvailableFreeSpace
    }
}

function Get-UindosRecentHotfixes {
    Assert-UindosCommand 'Get-HotFix'
    @(Get-HotFix -ErrorAction Stop |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [pscustomobject]@{
                hotfixId = [string]$_.HotFixID
                installedOn = if ($_.InstalledOn) { $_.InstalledOn.ToString('yyyy-MM-dd') } else { $null }
            }
        })
}
 -or
                $version -cnotmatch '^\d+\.\d+\.\d+\.\d+

function Get-UindosWin32Programs {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $apps = foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { continue }
            [pscustomobject]@{
                name = [string]$item.DisplayName
                version = [string]$item.DisplayVersion
                publisher = [string]$item.Publisher
            }
        }
    }
    @($apps | Sort-Object name, version, publisher -Unique)
}

function Get-UindosPrivacyPolicies {
    $settings = @(
        @('diagnostics.allowTelemetry.policy', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry'),
        @('diagnostics.allowTelemetry.legacy', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection', 'AllowTelemetry'),
        @('consumer.disableConsumerFeatures', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'DisableWindowsConsumerFeatures'),
        @('copilot.turnOffLegacyCopilot', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot'),
        @('advertising.currentUser', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled'),
        @('privacy.tailoredExperiences.currentUser', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled'),
        @('security.smartScreenExplorer', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer', 'SmartScreenEnabled'),
        @('security.smartScreenPolicy', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableSmartScreen'),
        @('security.uac', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA'),
        @('updates.useWsus', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'UseWUServer'),
        @('updates.noAutoUpdate', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'NoAutoUpdate'),
        @('updates.wsusServerPresent', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'WUServer')
    )
    foreach ($entry in $settings) {
        $setting = Get-UindosRegistrySetting -Id $entry[0] -Path $entry[1] -Name $entry[2]
        if ($setting.id -eq 'updates.wsusServerPresent') {
            # Do not publish internal organization URLs or network addresses.
            $setting.value = $null
        }
        $setting
    }
}

function Get-UindosServiceStatus {
    foreach ($name in @('wuauserv', 'BITS', 'UsoSvc', 'WaaSMedicSvc', 'WinDefend', 'MpsSvc', 'DiagTrack')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        [pscustomobject]@{
            name = $name
            installed = ($null -ne $service)
            status = if ($service) { [string]$service.Status } else { $null }
            startType = if ($service) { [string]$service.StartType } else { $null }
        }
    }
}

function Get-UindosDefenderStatus {
    Assert-UindosCommand 'Get-MpComputerStatus'
    $d = Get-MpComputerStatus -ErrorAction Stop
    [pscustomobject]@{
        antivirusEnabled = $d.AntivirusEnabled
        realTimeProtectionEnabled = $d.RealTimeProtectionEnabled
        tamperProtected = $d.IsTamperProtected
        signatureVersion = [string]$d.AntivirusSignatureVersion
    }
}

function Get-UindosFirewallStatus {
    Assert-UindosCommand 'Get-NetFirewallProfile'
    @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{ profile = [string]$_.Name; enabled = [bool]$_.Enabled }
    } | Sort-Object profile)
}

function Get-UindosBitLockerStatus {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Get-BitLockerVolume'
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    [pscustomobject]@{
        volumeType = [string]$volume.VolumeType
        protectionStatus = [string]$volume.ProtectionStatus
        volumeStatus = [string]$volume.VolumeStatus
        encryptionPercentage = $volume.EncryptionPercentage
    }
}

function Get-UindosSecureBootStatus {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Confirm-SecureBootUEFI'
    [pscustomobject]@{ enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) }
}

function Get-UindosSystemDisk {
    $drive = [System.IO.DriveInfo]::new("$($env:SystemDrive)\")
    if (-not $drive.IsReady) { throw 'System volume not ready.' }
    [pscustomobject]@{
        sizeBytes = [int64]$drive.TotalSize
        freeBytes = [int64]$drive.AvailableFreeSpace
    }
}

function Get-UindosRecentHotfixes {
    Assert-UindosCommand 'Get-HotFix'
    @(Get-HotFix -ErrorAction Stop |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [pscustomobject]@{
                hotfixId = [string]$_.HotFixID
                installedOn = if ($_.InstalledOn) { $_.InstalledOn.ToString('yyyy-MM-dd') } else { $null }
            }
        })
}
) {
                throw [System.IO.InvalidDataException]::new('Provisioned AppX record has invalid identity or version.')
            }
            [pscustomobject]@{ name = $name; version = $version }
        }
    )
    @($rows | Sort-Object name, version -Unique)
}

function ConvertFrom-UindosProvisionedAppxJson {
    param([Parameter(Mandatory)][string]$Json)

    try {
        $result = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    }
    catch {
        throw [System.IO.InvalidDataException]::new('Windows PowerShell returned invalid provisioning JSON.')
    }
    if ($null -eq $result -or $result.schema -cne 'uindos.provisioned-appx/v1' -or
        $null -eq $result.PSObject.Properties['packages'] -or
        $null -eq $result.packages -or $result.packages -isnot [array]) {
        throw [System.IO.InvalidDataException]::new('Windows PowerShell returned an invalid provisioning envelope.')
    }
    @(ConvertTo-UindosProvisionedAppxRows -Packages @($result.packages))
}

function Invoke-UindosProvisionedAppxWindowsPowerShell {
    # Invoke a fixed Windows system executable; never use PATH resolution.
    $exe = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw [System.NotSupportedException]::new('Windows PowerShell 5.1 is unavailable for the DISM compatibility fallback.')
    }
    # EncodedCommand avoids interpolation/quoting and passes no sensitive input.
    # The child emits ONLY compact schema-tagged JSON; no disk file is written.
    $command = @'
$ErrorActionPreference = 'Stop'
$WarningPreference = 'SilentlyContinue'
try {
    $packages = @(
        Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object {
            [pscustomobject]@{ name = [string]$_.DisplayName; version = [string]$_.Version }
        }
    )
    [pscustomobject]@{ schema = 'uindos.provisioned-appx/v1'; packages = $packages } |
        ConvertTo-Json -Depth 4 -Compress
}
catch {
    [Console]::Error.WriteLine('Provisioned AppX inventory failed in Windows PowerShell.')
    exit 1
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $output = @(& $exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded 2>$null)
    if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or
        [string]::IsNullOrWhiteSpace([string]$output[0])) {
        throw [System.InvalidOperationException]::new('Windows PowerShell 5.1 provisioning fallback failed.')
    }
    @(ConvertFrom-UindosProvisionedAppxJson -Json ([string]$output[0]))
}

function Get-UindosProvisionedAppx {
    [CmdletBinding()]
    param(
        [scriptblock]$PrimaryReader,
        [scriptblock]$FallbackReader,
        [switch]$SkipPlatformChecks
    )

    # The override parameters permit isolated mock tests without Windows APIs.
    if (-not $SkipPlatformChecks) {
        Assert-UindosAdministrator
        Assert-UindosCommand 'Get-AppxProvisionedPackage'
    }
    elseif ($null -eq $PrimaryReader -or $null -eq $FallbackReader) {
        throw [System.ArgumentException]::new('Mock mode requires both readers.')
    }

    if ($null -eq $PrimaryReader) {
        $PrimaryReader = { Get-AppxProvisionedPackage -Online -ErrorAction Stop }
    }
    if ($null -eq $FallbackReader) {
        $FallbackReader = { Invoke-UindosProvisionedAppxWindowsPowerShell }
    }
    try {
        $packages = @(& $PrimaryReader)
    }
    catch {
        if (-not (Test-UindosProvisionedAppxRegistrationFailure -Exception $_.Exception)) {
            throw
        }
        $packages = @(& $FallbackReader)
    }
    @(ConvertTo-UindosProvisionedAppxRows -Packages $packages)
}

function Get-UindosWin32Programs {
    $roots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $apps = foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -ErrorAction Stop)) { continue }
        foreach ($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)) {
            $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
            if ([string]::IsNullOrWhiteSpace([string]$item.DisplayName)) { continue }
            [pscustomobject]@{
                name = [string]$item.DisplayName
                version = [string]$item.DisplayVersion
                publisher = [string]$item.Publisher
            }
        }
    }
    @($apps | Sort-Object name, version, publisher -Unique)
}

function Get-UindosPrivacyPolicies {
    $settings = @(
        @('diagnostics.allowTelemetry.policy', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry'),
        @('diagnostics.allowTelemetry.legacy', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection', 'AllowTelemetry'),
        @('consumer.disableConsumerFeatures', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent', 'DisableWindowsConsumerFeatures'),
        @('copilot.turnOffLegacyCopilot', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot', 'TurnOffWindowsCopilot'),
        @('advertising.currentUser', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled'),
        @('privacy.tailoredExperiences.currentUser', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled'),
        @('security.smartScreenExplorer', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer', 'SmartScreenEnabled'),
        @('security.smartScreenPolicy', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System', 'EnableSmartScreen'),
        @('security.uac', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System', 'EnableLUA'),
        @('updates.useWsus', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'UseWUServer'),
        @('updates.noAutoUpdate', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'NoAutoUpdate'),
        @('updates.wsusServerPresent', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'WUServer')
    )
    foreach ($entry in $settings) {
        $setting = Get-UindosRegistrySetting -Id $entry[0] -Path $entry[1] -Name $entry[2]
        if ($setting.id -eq 'updates.wsusServerPresent') {
            # Do not publish internal organization URLs or network addresses.
            $setting.value = $null
        }
        $setting
    }
}

function Get-UindosServiceStatus {
    foreach ($name in @('wuauserv', 'BITS', 'UsoSvc', 'WaaSMedicSvc', 'WinDefend', 'MpsSvc', 'DiagTrack')) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        [pscustomobject]@{
            name = $name
            installed = ($null -ne $service)
            status = if ($service) { [string]$service.Status } else { $null }
            startType = if ($service) { [string]$service.StartType } else { $null }
        }
    }
}

function Get-UindosDefenderStatus {
    Assert-UindosCommand 'Get-MpComputerStatus'
    $d = Get-MpComputerStatus -ErrorAction Stop
    [pscustomobject]@{
        antivirusEnabled = $d.AntivirusEnabled
        realTimeProtectionEnabled = $d.RealTimeProtectionEnabled
        tamperProtected = $d.IsTamperProtected
        signatureVersion = [string]$d.AntivirusSignatureVersion
    }
}

function Get-UindosFirewallStatus {
    Assert-UindosCommand 'Get-NetFirewallProfile'
    @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{ profile = [string]$_.Name; enabled = [bool]$_.Enabled }
    } | Sort-Object profile)
}

function Get-UindosBitLockerStatus {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Get-BitLockerVolume'
    $volume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction Stop
    [pscustomobject]@{
        volumeType = [string]$volume.VolumeType
        protectionStatus = [string]$volume.ProtectionStatus
        volumeStatus = [string]$volume.VolumeStatus
        encryptionPercentage = $volume.EncryptionPercentage
    }
}

function Get-UindosSecureBootStatus {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Confirm-SecureBootUEFI'
    [pscustomobject]@{ enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop) }
}

function Get-UindosSystemDisk {
    $drive = [System.IO.DriveInfo]::new("$($env:SystemDrive)\")
    if (-not $drive.IsReady) { throw 'System volume not ready.' }
    [pscustomobject]@{
        sizeBytes = [int64]$drive.TotalSize
        freeBytes = [int64]$drive.AvailableFreeSpace
    }
}

function Get-UindosRecentHotfixes {
    Assert-UindosCommand 'Get-HotFix'
    @(Get-HotFix -ErrorAction Stop |
        Sort-Object InstalledOn -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            [pscustomobject]@{
                hotfixId = [string]$_.HotFixID
                installedOn = if ($_.InstalledOn) { $_.InstalledOn.ToString('yyyy-MM-dd') } else { $null }
            }
        })
}
