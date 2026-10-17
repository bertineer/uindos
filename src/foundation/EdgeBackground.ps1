# Reversible Edge background policy defaults. Preserve Edge Update and WebView2.
# Microsoft policy references: StartupBoostEnabled (Windows >= Edge 88) and
# BackgroundModeEnabled (Windows >= Edge 77); both support dynamic refresh.

function Get-UindosEdgeBackgroundPolicyCatalog {
    return @(
        [pscustomobject]@{
            id = 'edge.startup-boost-disabled'
            path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
            name = 'StartupBoostEnabled'
            kind = 'DWord'
            value = 0
        },
        [pscustomobject]@{
            id = 'edge.background-mode-disabled'
            path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
            name = 'BackgroundModeEnabled'
            kind = 'DWord'
            value = 0
        }
    )
}

function Assert-UindosEdgeBackgroundAction {
    param([Parameter(Mandatory)]$Action)
    $rule = @(Get-UindosEdgeBackgroundPolicyCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($rule.Count -ne 1 -or $rule[0].path -cne [string]$Action.path -or
        $rule[0].name -cne [string]$Action.name -or $rule[0].kind -cne [string]$Action.kind -or
        ($Action.value -isnot [int] -and $Action.value -isnot [long]) -or
        $Action.value -ne $rule[0].value) {
        throw [System.NotSupportedException]::new('Edge background action differs from the fixed policy allowlist.')
    }
}

function Assert-UindosEdgeBackgroundTarget {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (@(Get-UindosEdgeBackgroundPolicyCatalog | Where-Object { $_.path -ceq $Path -and $_.name -ceq $Name }).Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside the Edge background policy allowlist.')
    }
}

function ConvertTo-UindosEdgeBackgroundDword {
    param([Parameter(Mandatory)]$Value)
    # Prior DWORDs are read as signed Int32 and journals can reload them as Int64.
    if (($Value -isnot [int] -and $Value -isnot [long]) -or
        $Value -lt [int]::MinValue -or $Value -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('Edge background prior value must be an integer in the signed DWORD range.')
    }
    return [int]$Value
}

function Get-UindosInstalledEdgeVersion {
    [CmdletBinding()]
    param()
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Installed Edge version detection requires Windows.')
    }

    # Edge Stable's Microsoft Edge Update product ID. Read machine metadata only;
    # do not launch msedge.exe or an updater process to discover the version.
    $productId = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\$productId",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\$productId"
    )
    $versions = [System.Collections.Generic.List[version]]::new()
    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path -ErrorAction Stop)) { continue }
        $key = Get-Item -LiteralPath $path -ErrorAction Stop
        if (@($key.GetValueNames()) -cnotcontains 'name' -or @($key.GetValueNames()) -cnotcontains 'pv') { continue }
        if ($key.GetValueKind('name').ToString() -cne 'String' -or
            $key.GetValueKind('pv').ToString() -cne 'String') { continue }
        if ([string]$key.GetValue('name',$null) -cne 'Microsoft Edge') { continue }
        [version]$version = $null
        if ([version]::TryParse([string]$key.GetValue('pv',$null), [ref]$version)) {
            $versions.Add($version)
        }
    }
    if ($versions.Count -eq 0) {
        throw [System.NotSupportedException]::new('A valid machine Microsoft Edge Stable version was not found in Edge Update Clients metadata.')
    }
    return ($versions | Sort-Object -Descending | Select-Object -First 1).ToString()
}

function Get-UindosEdgeBackgroundActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)
    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Edge background policies require Windows 11 Pro and a supported installed Edge version.')
        }
        $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $OsInfo = [pscustomobject]@{
            editionId = [string]$os.EditionID
            build = [string]$os.CurrentBuildNumber
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            edgeVersion = Get-UindosInstalledEdgeVersion
        }
    }

    [long]$build = 0
    [version]$edgeVersion = $null
    if ($null -eq $OsInfo -or
        [string]$OsInfo.editionId -cnotin @('Professional','ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build,[ref]$build) -or $build -lt 22000 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64') -or
        -not [version]::TryParse([string]$OsInfo.edgeVersion,[ref]$edgeVersion) -or
        $edgeVersion.Major -lt 88) {
        throw [System.NotSupportedException]::new(
            'Edge background policies require Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later, and installed Microsoft Edge Stable 88 or later.'
        )
    }
    return @(Get-UindosEdgeBackgroundPolicyCatalog)
}

function Test-UindosEdgeBackgroundAdministrator {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-UindosEdgeBackgroundWriteAuthorization {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$IsAdministrator)
    if (-not $IsAdministrator) {
        throw 'Edge background policy Apply and Undo require an already elevated PowerShell process; no elevation was attempted.'
    }
}

function Get-UindosEdgeBackgroundJournalDirectory {
    [CmdletBinding()]
    param(
        [Parameter()][string]$JournalDirectory,
        [Parameter()][bool]$HasOverride,
        [Parameter()][string]$LocalAppData
    )
    if ($HasOverride) {
        if ([string]::IsNullOrWhiteSpace($JournalDirectory) -or
            -not [IO.Path]::IsPathFullyQualified($JournalDirectory)) {
            throw 'JournalDirectory must be a valid absolute path.'
        }
        try { $resolved = [IO.Path]::GetFullPath($JournalDirectory) }
        catch { throw 'JournalDirectory must be a valid absolute path.' }
        if ((Test-Path -LiteralPath $resolved) -and
            -not (Test-Path -LiteralPath $resolved -PathType Container)) {
            throw 'JournalDirectory exists but is not a directory.'
        }
        return $resolved
    }
    if ([string]::IsNullOrWhiteSpace($LocalAppData)) {
        throw 'LOCALAPPDATA is unavailable. Refusing to store transaction journal.'
    }
    return Join-Path $LocalAppData 'uindos\transactions\edge-background-v1'
}

function New-UindosEdgeBackgroundAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Edge background policy registry access requires Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosEdgeBackgroundAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosEdgeBackgroundTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                throw [System.NotSupportedException]::new("Existing Edge policy '$Name' is not DWORD.")
            }
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=[int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosEdgeBackgroundTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw 'Edge background adapter only writes DWORD values.' }
            $safeValue = ConvertTo-UindosEdgeBackgroundDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $safeValue -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosEdgeBackgroundTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
