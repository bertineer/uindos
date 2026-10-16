# Curated, best-effort per-user Windows 11 notifications and re-onboarding
# preferences. NOT Windows OOBE bypass, servicing controls or Pro CSP claims.
function Get-UindosWelcomeCatalog {
    return @(
        [pscustomobject]@{
            id = 'welcome.hide-post-update-welcome'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            name = 'SubscribedContent-310093Enabled'; kind = 'DWord'; value = 0
        }
        [pscustomobject]@{
            id = 'welcome.hide-tips'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
            name = 'SubscribedContent-338389Enabled'; kind = 'DWord'; value = 0
        }
        [pscustomobject]@{
            id = 'welcome.hide-finish-setup-prompt'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement'
            name = 'ScoobeSystemSettingEnabled'; kind = 'DWord'; value = 0
        }
    )
}

function Assert-UindosWelcomeAction {
    param([Parameter(Mandatory)]$Action)
    $items = @(Get-UindosWelcomeCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($items.Count -ne 1 -or
        $items[0].path -cne [string]$Action.path -or
        $items[0].name -cne [string]$Action.name -or
        $items[0].kind -cne [string]$Action.kind -or
        [string]$items[0].value -cne [string]$Action.value) {
        throw [System.NotSupportedException]::new('Welcome action differs from curated defaults.')
    }
}

function Assert-UindosWelcomeTarget {
    param([string]$Path, [string]$Name)
    $items = @(Get-UindosWelcomeCatalog | Where-Object {
        $_.path -ceq $Path -and $_.name -ceq $Name
    })
    if ($items.Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside welcome allowlist.')
    }
}

function Get-UindosWelcomeActions {
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
        throw [System.NotSupportedException]::new('Welcome prefs require Windows 11 Pro/Pro N x64/ARM64.')
    }
    return @(Get-UindosWelcomeCatalog)
}

function New-UindosWelcomeAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Welcome registry preferences require Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosWelcomeAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosWelcomeTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                throw [System.NotSupportedException]::new('Existing welcome value is not DWORD.')
            }
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=[int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosWelcomeTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord' -or [string]$Value -cnotmatch '^[0-9]+$' -or [long]$Value -gt [int]::MaxValue) {
                throw 'Welcome adapter only writes DWORD values.'
            }
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value ([int]$Value) -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosWelcomeTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
