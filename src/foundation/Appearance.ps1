# One curated current-user appearance configuration. The API adapter uses the
# existing engine's fixed-target state contract; synthetic targets are not keys.
. (Join-Path $PSScriptRoot 'Theme.ps1')
. (Join-Path $PSScriptRoot 'DesktopBackground.ps1')

function Get-UindosAppearanceActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)
    $parameters = @{}
    if ($PSBoundParameters.ContainsKey('OsInfo')) { $parameters.OsInfo = $OsInfo }
    return @(@(Get-UindosThemeActions @parameters) + @(Get-UindosDesktopBackgroundActions))
}

function Assert-UindosAppearanceContext {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Appearance changes require a Windows desktop session.')
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run appearance Apply/Undo from a non-elevated desktop PowerShell; no elevation was attempted.'
    }
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
        Where-Object { $_.SessionId -eq $sessionId })
    $sameUser = @($explorer | ForEach-Object {
        (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop).Sid
    } | Where-Object { $_ -eq $identity.User.Value }).Count -gt 0
    if (-not $sameUser) { throw 'Appearance changes require the same user and session as Explorer.' }
}

function New-UindosAppearanceAdapter {
    [CmdletBinding()]
    param([hashtable]$ThemeAdapter, [hashtable]$DesktopAdapter)
    if (-not $PSBoundParameters.ContainsKey('ThemeAdapter')) { $ThemeAdapter = New-UindosThemeAdapter }
    if (-not $PSBoundParameters.ContainsKey('DesktopAdapter')) { $DesktopAdapter = New-UindosDesktopBackgroundAdapter }
    Assert-UindosAdapter -Adapter $ThemeAdapter
    Assert-UindosAdapter -Adapter $DesktopAdapter
    return @{
        ValidateAction = {
            param($Action)
            if ([string]$Action.path -ceq 'desktop:background') {
                Assert-UindosDesktopBackgroundAction -Action $Action
            } else { Assert-UindosThemeAction -Action $Action }
        }
        Read = {
            param([string]$Path, [string]$Name)
            if ($Path -ceq 'desktop:background') {
                Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
                & $DesktopAdapter.Read $Path $Name
            } else {
                Assert-UindosThemeTarget -Path $Path -Name $Name
                & $ThemeAdapter.Read $Path $Name
            }
        }.GetNewClosure()
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            if ($Path -ceq 'desktop:background') {
                Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
                & $DesktopAdapter.Write $Path $Name $Kind $Value
            } else {
                Assert-UindosThemeTarget -Path $Path -Name $Name
                & $ThemeAdapter.Write $Path $Name $Kind $Value
            }
        }.GetNewClosure()
        Remove = {
            param([string]$Path, [string]$Name)
            if ($Path -ceq 'desktop:background') {
                Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
                & $DesktopAdapter.Remove $Path $Name
            } else {
                Assert-UindosThemeTarget -Path $Path -Name $Name
                & $ThemeAdapter.Remove $Path $Name
            }
        }.GetNewClosure()
    }
}
