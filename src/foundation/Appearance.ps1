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
    $hasThemeAdapter = $PSBoundParameters.ContainsKey('ThemeAdapter')
    $hasDesktopAdapter = $PSBoundParameters.ContainsKey('DesktopAdapter')

    # Keep the trusted child adapters and their private helper functions in a
    # private module session state. A caller can invoke this returned adapter
    # after the script that dot-sourced Appearance.ps1 has exited, so lexical
    # function lookup and GetNewClosure are not sufficient for routing.
    $routerModule = New-Module -ArgumentList $PSScriptRoot -ScriptBlock {
        param([string]$FoundationPath)
        . (Join-Path $FoundationPath 'Theme.ps1')
        . (Join-Path $FoundationPath 'DesktopBackground.ps1')
    }
    return & $routerModule {
        param($ChildThemeAdapter, $ChildDesktopAdapter, [bool]$HasThemeAdapter, [bool]$HasDesktopAdapter)
        if (-not $HasThemeAdapter) { $ChildThemeAdapter = New-UindosThemeAdapter }
        if (-not $HasDesktopAdapter) { $ChildDesktopAdapter = New-UindosDesktopBackgroundAdapter }
        foreach ($child in @($ChildThemeAdapter, $ChildDesktopAdapter)) {
            if ($null -eq $child) { throw 'A trusted child appearance adapter is required.' }
            foreach ($method in @('Read','Write','Remove')) {
                if (-not $child.ContainsKey($method) -or $child[$method] -isnot [scriptblock]) {
                    throw "Appearance child adapter missing trusted '$method' operation."
                }
            }
        }
        # These module-scoped references remain private to this adapter's
        # module instance and are visible to its returned scriptblocks.
        $script:UindosAppearanceThemeAdapter = $ChildThemeAdapter
        $script:UindosAppearanceDesktopAdapter = $ChildDesktopAdapter
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
                    & $script:UindosAppearanceDesktopAdapter.Read $Path $Name
                } else {
                    Assert-UindosThemeTarget -Path $Path -Name $Name
                    & $script:UindosAppearanceThemeAdapter.Read $Path $Name
                }
            }
            Write = {
                param([string]$Path, [string]$Name, [string]$Kind, $Value)
                if ($Path -ceq 'desktop:background') {
                    Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
                    & $script:UindosAppearanceDesktopAdapter.Write $Path $Name $Kind $Value
                } else {
                    Assert-UindosThemeTarget -Path $Path -Name $Name
                    & $script:UindosAppearanceThemeAdapter.Write $Path $Name $Kind $Value
                }
            }
            Remove = {
                param([string]$Path, [string]$Name)
                if ($Path -ceq 'desktop:background') {
                    Assert-UindosDesktopBackgroundTarget -Path $Path -Name $Name
                    & $script:UindosAppearanceDesktopAdapter.Remove $Path $Name
                } else {
                    Assert-UindosThemeTarget -Path $Path -Name $Name
                    & $script:UindosAppearanceThemeAdapter.Remove $Path $Name
                }
            }
        }
    } $ThemeAdapter $DesktopAdapter $hasThemeAdapter $hasDesktopAdapter
}
