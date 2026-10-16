# uindos v1 privacy defaults. Windows 11 Pro, per-user, deliberately small.
# One curated set of actions; this is not a generic tweak catalog.
# Official policy references are in docs/research/PRIVACY-DEFAULTS.md.

function Get-UindosPrivacyRuleCatalog {
    return @(
        [pscustomobject]@{
            id = 'privacy.tailored-experiences'
            path = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
            name = 'DisableTailoredExperiencesWithDiagnosticData'
            kind = 'DWord'
            value = 1
            evidence = 'documented-user-policy'
        },
        [pscustomobject]@{
            id = 'privacy.third-party-suggestions'
            path = 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
            name = 'DisableThirdPartySuggestions'
            kind = 'DWord'
            value = 1
            evidence = 'documented-user-policy'
        },
        [pscustomobject]@{
            id = 'privacy.advertising-id-current-user'
            path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'
            name = 'Enabled'
            kind = 'DWord'
            value = 0
            evidence = 'user-preference-best-effort'
        }
    )
}

function Assert-UindosPrivacyAction {
    param([Parameter(Mandatory)]$Action)
    $matching = @(Get-UindosPrivacyRuleCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($matching.Count -ne 1) {
        throw [System.NotSupportedException]::new('Action ID is not in the uindos privacy allowlist.')
    }
    $rule = $matching[0]
    if ($rule.path -cne [string]$Action.path -or
        $rule.name -cne [string]$Action.name -or
        $rule.kind -cne [string]$Action.kind -or
        [string]$rule.value -cne [string]$Action.value) {
        throw [System.NotSupportedException]::new('Action differs from the fixed uindos privacy default.')
    }
}

function Assert-UindosPrivacyTarget {
    param([Parameter(Mandatory)][string]$Path,
          [Parameter(Mandatory)][string]$Name)
    $matched = @(Get-UindosPrivacyRuleCatalog | Where-Object {
        $_.path -ceq $Path -and $_.name -ceq $Name
    })
    if ($matched.Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is not in the privacy allowlist.')
    }
}

function Get-UindosPrivacyActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)

    # Test-only OS injection; default checks installed Windows metadata.
    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Privacy defaults require Windows 11 Pro.')
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
            'Privacy v1 targets Windows 11 Pro/Pro N x64 or ARM64 only. Other editions/builds are unvalidated.'
        )
    }

    return @(Get-UindosPrivacyRuleCatalog)
}

function New-UindosPrivacyAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Windows Registry is required.')
    }
    # Explicit allowlists here and in the engine's ValidateAction path:
    # a user-supplied action cannot select any other key, name, kind or value.
    return @{
        ValidateAction = { param($Action) Assert-UindosPrivacyAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosPrivacyTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
            }
            if ($key.GetValueKind($Name).ToString() -cne 'DWord') {
                throw [System.NotSupportedException]::new('Existing privacy value is not DWORD; refusing to coerce it.')
            }
            return [pscustomobject]@{ exists = $true; kind = 'DWord'; value = [int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosPrivacyTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord' -or $Value -isnot [int]) {
                throw 'Privacy adapter only writes DWORD integer values.'
            }
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosPrivacyTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
