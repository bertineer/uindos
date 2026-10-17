# Best-effort Windows 11 Pro policy for File Explorer search suggestions.
# This fixed policy does not establish that Start web results are blocked.

function Get-UindosSearchSuggestionsCatalog {
    return @(
        [pscustomobject]@{
            id = 'search.disable-box-suggestions'
            path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
            name = 'DisableSearchBoxSuggestions'
            kind = 'DWord'
            value = 1
            evidence = 'documented-user-policy-best-effort'
        }
    )
}

function Get-UindosSearchSuggestionsActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)

    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Search suggestions policy requires Windows 11 Pro.')
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
        -not [long]::TryParse([string]$OsInfo.build, [ref]$build) -or
        $build -lt 22000 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64')) {
        throw [System.NotSupportedException]::new(
            'Search suggestions v1 targets Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later.'
        )
    }
    return @(Get-UindosSearchSuggestionsCatalog)
}

function Assert-UindosSearchSuggestionsAction {
    param([Parameter(Mandatory)]$Action)
    $rule = (Get-UindosSearchSuggestionsCatalog)[0]
    if ($Action.id -isnot [string] -or $Action.path -isnot [string] -or
        $Action.name -isnot [string] -or $Action.kind -isnot [string] -or
        ($Action.value -isnot [int] -and $Action.value -isnot [long]) -or
        $Action.id -cne $rule.id -or $Action.path -cne $rule.path -or
        $Action.name -cne $rule.name -or $Action.kind -cne $rule.kind -or
        $Action.value -ne $rule.value) {
        throw [System.NotSupportedException]::new('Action differs from the fixed search suggestions policy.')
    }
}

function Assert-UindosSearchSuggestionsTarget {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Name)
    $rule = (Get-UindosSearchSuggestionsCatalog)[0]
    if ($Path -cne $rule.path -or $Name -cne $rule.name) {
        throw [System.NotSupportedException]::new('Registry target is not in the search suggestions allowlist.')
    }
}

function ConvertTo-UindosSearchSuggestionsDword {
    param([Parameter(Mandatory)]$Value)
    if (($Value -isnot [int] -and $Value -isnot [long]) -or
        $Value -lt [int]::MinValue -or $Value -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('Search suggestions prior value must be an integer in the signed DWORD range.')
    }
    return [int]$Value
}

function Assert-UindosSearchSuggestionsContext {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Search suggestions changes require a Windows desktop session.')
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run search suggestions Apply/Undo from an elevated PowerShell in the desktop user session; no elevation was attempted.'
    }
    $sessionId = (Get-Process -Id $PID).SessionId
    $explorer = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
        Where-Object { $_.SessionId -eq $sessionId })
    $sameUser = @($explorer | ForEach-Object {
        (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid -ErrorAction Stop).Sid
    } | Where-Object { $_ -eq $identity.User.Value }).Count -gt 0
    if (-not $sameUser) { throw 'Search suggestions changes require an elevated process for the same user and session as Explorer.' }
}

function New-UindosSearchSuggestionsAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Windows Registry is required.')
    }

    return @{
        ValidateAction = { param($Action) Assert-UindosSearchSuggestionsAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosSearchSuggestionsTarget -Path $Path -Name $Name
            $subKeyPath = $Path.Substring('HKCU:\'.Length)
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $false)
            if ($null -eq $key) {
                return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
            }
            try {
                if (@($key.GetValueNames()) -cnotcontains $Name) {
                    return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
                }
                if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                    throw [System.NotSupportedException]::new('Existing search suggestions value is not DWORD; refusing to coerce it.')
                }
                return [pscustomobject]@{ exists = $true; kind = 'DWord'; value = [int]$key.GetValue($Name, $null) }
            }
            finally { $key.Dispose() }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosSearchSuggestionsTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw 'Search suggestions adapter only writes DWORD integer values.' }
            $safeValue = ConvertTo-UindosSearchSuggestionsDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $safeValue -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosSearchSuggestionsTarget -Path $Path -Name $Name
            $subKeyPath = $Path.Substring('HKCU:\'.Length)
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $false)
            if ($null -eq $key) { return }
            try { $exists = @($key.GetValueNames()) -ccontains $Name }
            finally { $key.Dispose() }
            if ($exists) { Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop }
        }
    }
}
