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

function Get-UindosProvisionedAppx {
    Assert-UindosAdministrator
    Assert-UindosCommand 'Get-AppxProvisionedPackage'
    @(Get-AppxProvisionedPackage -Online -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            name = [string]$_.DisplayName
            version = [string]$_.Version
        }
    } | Sort-Object name, version)
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
