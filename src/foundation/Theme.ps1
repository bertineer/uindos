# Curated per-user dark-mode preferences. The documented registry mapping is
# limited to the two color-mode DWORDs; no accent, transparency, or theme files.
function Get-UindosThemeCatalog {
    return @(
        [pscustomobject]@{
            id = 'theme.dark-apps'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            name = 'AppsUseLightTheme'; kind = 'DWord'; value = 0
        }
        [pscustomobject]@{
            id = 'theme.dark-system'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            name = 'SystemUsesLightTheme'; kind = 'DWord'; value = 0
        }
    )
}

function Assert-UindosThemeAction {
    param([Parameter(Mandatory)]$Action)
    $items = @(Get-UindosThemeCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($items.Count -ne 1 -or
        $items[0].path -cne [string]$Action.path -or
        $items[0].name -cne [string]$Action.name -or
        $items[0].kind -cne [string]$Action.kind -or
        [string]$items[0].value -cne [string]$Action.value) {
        throw [System.NotSupportedException]::new('Theme action differs from curated defaults.')
    }
}

function Assert-UindosThemeTarget {
    param([string]$Path, [string]$Name)
    $items = @(Get-UindosThemeCatalog | Where-Object {
        $_.path -ceq $Path -and $_.name -ceq $Name
    })
    if ($items.Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside theme allowlist.')
    }
}

function ConvertTo-UindosThemeDword {
    param([Parameter(Mandatory)]$Value)
    $digits = [string]$Value
    [long]$number = 0
    if ($digits -cnotmatch '^[0-9]+$' -or
        -not [long]::TryParse($digits, [ref]$number) -or
        $number -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('Theme DWORD is outside the supported nonnegative Int32 range.')
    }
    return [int]$number
}

function Get-UindosThemeActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)
    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
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
    if ($null -eq $OsInfo -or
        [string]$OsInfo.editionId -cnotin @('Professional','ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build,[ref]$build) -or
        $build -lt 22000 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64')) {
        throw [System.NotSupportedException]::new('Theme prefs require Windows 11 Pro/Pro N x64/ARM64.')
    }
    return @(Get-UindosThemeCatalog)
}

function New-UindosThemeAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Theme registry preferences require Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosThemeAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosThemeTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                throw [System.NotSupportedException]::new('Existing theme value is not DWORD.')
            }
            $value = ConvertTo-UindosThemeDword -Value $key.GetValue($Name,$null)
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=$value }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosThemeTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw [System.NotSupportedException]::new('Theme adapter only writes DWORD values.') }
            $number = ConvertTo-UindosThemeDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $number -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosThemeTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}

# Call once after a successful theme transaction. The notification is bounded
# per window and best-effort; callers should report it separately from registry IO.
function Invoke-UindosThemeRefresh {
    [CmdletBinding()]
    param()
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        return [pscustomobject]@{ notified=$false; reason='unsupported-platform'; timedOut=$false }
    }
    try {
        if (-not ('Uindos.Theme.NativeMethods' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Uindos.Theme {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
    }
}
'@ -ErrorAction Stop
        }
        [UIntPtr]$messageResult = [UIntPtr]::Zero
        $sent = [Uindos.Theme.NativeMethods]::SendMessageTimeout(
            [IntPtr]::new(0xffff), 0x001A, [UIntPtr]::Zero, 'ImmersiveColorSet', 0x0002, 2000, [ref]$messageResult)
        return [pscustomobject]@{ notified=($sent -ne [IntPtr]::Zero); reason=if ($sent -eq [IntPtr]::Zero) { 'timeout-or-no-window-response' } else { 'sent' }; timedOut=if ($sent -eq [IntPtr]::Zero) { $null } else { $false } }
    }
    catch {
        return [pscustomobject]@{ notified=$false; reason='notification-error'; timedOut=$false }
    }
}
