# One supported, reversible Windows 11 Pro Widgets policy.
# This only targets the News and Interests policy; it does not prove every
# Widgets surface (including lock-screen experiences) is disabled.
function Get-UindosWidgetsPolicyCatalog {
    return @(
        [pscustomobject]@{
            id = 'widgets.disable-news-and-interests'
            path = 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
            name = 'AllowNewsAndInterests'
            kind = 'DWord'
            value = 0
        }
    )
}

function Assert-UindosWidgetsAction {
    param([Parameter(Mandatory)]$Action)
    $rule = @(Get-UindosWidgetsPolicyCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($rule.Count -ne 1 -or $rule[0].path -cne [string]$Action.path -or
        $rule[0].name -cne [string]$Action.name -or $rule[0].kind -cne [string]$Action.kind -or
        [string]$rule[0].value -cne [string]$Action.value) {
        throw [System.NotSupportedException]::new('Widgets action differs from the supported policy allowlist.')
    }
}

function Assert-UindosWidgetsTarget {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (@(Get-UindosWidgetsPolicyCatalog | Where-Object { $_.path -ceq $Path -and $_.name -ceq $Name }).Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside the Widgets policy allowlist.')
    }
}

function ConvertTo-UindosWidgetsDword {
    param([Parameter(Mandatory)]$Value)
    # Desired state is fixed to zero by ValidateAction. Writes also restore a
    # captured prior DWORD, so allow the engine's signed Int32 representation.
    $digits = [string]$Value
    [int]$number = 0
    if ($digits -cnotmatch '^-?[0-9]+$' -or -not [int]::TryParse($digits,[ref]$number)) {
        throw [System.NotSupportedException]::new('Widgets policy value is outside the supported DWORD range.')
    }
    return $number
}

function Get-UindosWidgetsActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)
    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Widgets policy requires Windows 11 Pro.')
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
        throw [System.NotSupportedException]::new('Widgets policy requires Windows 11 Pro/Pro N x64/ARM64, build 22000 or later.')
    }
    return @(Get-UindosWidgetsPolicyCatalog)
}

function Test-UindosAdministrator {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-UindosWidgetsAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Widgets policy registry access requires Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosWidgetsAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosWidgetsTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                throw [System.NotSupportedException]::new('Existing Widgets policy value is not DWORD.')
            }
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=[int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosWidgetsTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw 'Widgets adapter only writes DWORD values.' }
            $safeValue = ConvertTo-UindosWidgetsDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $safeValue -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosWidgetsTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
