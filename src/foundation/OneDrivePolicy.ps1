# Reversible, single-value Windows OneDrive file storage policy.
# Microsoft policy: DisableOneDriveFileSync / DisableFileSyncNGSC.
# This blocks the sync/file-storage integration when enforced; it does not
# guarantee that OneDrive will not be reinstalled.

function Get-UindosOneDrivePolicyCatalog {
    @(
        [pscustomobject]@{
            id = 'onedrive.disable-file-sync'
            path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
            name = 'DisableFileSyncNGSC'
            kind = 'DWord'
            value = 1
        }
    )
}

function Assert-UindosOneDrivePolicyAction {
    param([Parameter(Mandatory)]$Action)
    $rule = @(Get-UindosOneDrivePolicyCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($rule.Count -ne 1 -or $rule[0].path -cne [string]$Action.path -or
        $rule[0].name -cne [string]$Action.name -or $rule[0].kind -cne [string]$Action.kind -or
        ($Action.value -isnot [int] -and $Action.value -isnot [long]) -or
        [long]$Action.value -ne 1) {
        throw [System.NotSupportedException]::new('OneDrive action differs from the single supported file-sync policy allowlist.')
    }
}

function Assert-UindosOneDrivePolicyTarget {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (@(Get-UindosOneDrivePolicyCatalog | Where-Object { $_.path -ceq $Path -and $_.name -ceq $Name }).Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside the OneDrive file-sync policy allowlist.')
    }
}

function ConvertTo-UindosOneDrivePolicyDword {
    param([Parameter(Mandatory)]$Value)
    # Registry reads produce Int32; JSON journals may deserialize it as Int64.
    if (($Value -isnot [int] -and $Value -isnot [long]) -or
        [long]$Value -lt [int]::MinValue -or [long]$Value -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('OneDrive policy prior value must be an integer in the signed DWORD range.')
    }
    return [int]$Value
}

function Assert-UindosOneDrivePolicyDwordKind {
    param([Parameter(Mandatory)][string]$Kind)
    if ($Kind -cne 'DWord') {
        throw [System.NotSupportedException]::new("Existing OneDrive policy '$((Get-UindosOneDrivePolicyCatalog)[0].name)' is not DWORD.")
    }
}

function Get-UindosOneDrivePolicyActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)
    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('OneDrive file-sync policy requires Windows 11 Pro.')
        }
        $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $OsInfo = [pscustomobject]@{
            editionId = [string]$os.EditionID
            build = [string]$os.CurrentBuildNumber
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        }
    }
    [long]$build = 0
    if ($null -eq $OsInfo -or [string]$OsInfo.editionId -cnotin @('Professional','ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build, [ref]$build) -or $build -lt 22000 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64')) {
        throw [System.NotSupportedException]::new('OneDrive file-sync policy requires Windows 11 Pro/Pro N x64/ARM64, build 22000 or later.')
    }
    return @(Get-UindosOneDrivePolicyCatalog)
}

function Test-UindosOneDrivePolicyAdministrator {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-UindosOneDrivePolicyWriteAuthorization {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$IsAdministrator)
    if (-not $IsAdministrator) {
        throw 'OneDrive policy Apply and Undo require an already elevated PowerShell process; no elevation was attempted.'
    }
}

function Get-UindosOneDrivePolicyJournalDirectory {
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
    return Join-Path $LocalAppData 'uindos\transactions\onedrive-policy-v1'
}

function New-UindosOneDrivePolicyAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('OneDrive file-sync policy registry access requires Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosOneDrivePolicyAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosOneDrivePolicyTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            Assert-UindosOneDrivePolicyDwordKind -Kind $key.GetValueKind($Name).ToString()
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=[int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosOneDrivePolicyTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw 'OneDrive policy adapter only writes DWORD values.' }
            $safeValue = ConvertTo-UindosOneDrivePolicyDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $safeValue -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosOneDrivePolicyTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
