# Three curated, current-user Windows 11 taskbar visibility preferences.
# No Start/taskbar pin database edits; no disabling Windows Search or Widgets.
function Get-UindosTaskbarCatalog {
    return @(
        [pscustomobject]@{
            id = 'taskbar.hide-widgets'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            name = 'TaskbarDa'; kind = 'DWord'; value = 0
        }
        [pscustomobject]@{
            id = 'taskbar.hide-taskview'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            name = 'ShowTaskViewButton'; kind = 'DWord'; value = 0
        }
        [pscustomobject]@{
            id = 'taskbar.hide-search'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            name = 'SearchboxTaskbarMode'; kind = 'DWord'; value = 0
        }
    )
}

function Assert-UindosTaskbarAction {
    param([Parameter(Mandatory)]$Action)
    $items = @(Get-UindosTaskbarCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($items.Count -ne 1 -or
        $items[0].path -cne [string]$Action.path -or
        $items[0].name -cne [string]$Action.name -or
        $items[0].kind -cne [string]$Action.kind -or
        [string]$items[0].value -cne [string]$Action.value) {
        throw [System.NotSupportedException]::new('Taskbar action differs from curated defaults.')
    }
}

function Assert-UindosTaskbarTarget {
    param([string]$Path, [string]$Name)
    $items = @(Get-UindosTaskbarCatalog | Where-Object {
        $_.path -ceq $Path -and $_.name -ceq $Name
    })
    if ($items.Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside taskbar allowlist.')
    }
}

function Get-UindosTaskbarActions {
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
        throw [System.NotSupportedException]::new('Taskbar prefs require Windows 11 Pro/Pro N x64/ARM64.')
    }
    return @(Get-UindosTaskbarCatalog)
}

function New-UindosTaskbarAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Taskbar registry preferences require Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosTaskbarAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosTaskbarTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                throw [System.NotSupportedException]::new('Existing taskbar value is not DWORD.')
            }
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=[int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosTaskbarTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord' -or [string]$Value -cnotmatch '^[0-9]+$' -or [long]$Value -gt [int]::MaxValue) {
                throw 'Taskbar adapter only writes DWORD values.'
            }
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value ([int]$Value) -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosTaskbarTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
 -or [long]$Value -gt [int]::MaxValue) {
                throw 'Taskbar adapter only writes DWORD values.'
            }
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosTaskbarTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
