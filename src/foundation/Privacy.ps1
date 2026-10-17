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

function ConvertTo-UindosPrivacyDword {
    param([Parameter(Mandatory)]$Value)
    # Registry reads use signed Int32, but JSON journals reload integers as
    # Int64. Preserve all 32 bits of prior DWORDs without coercing other types.
    if (($Value -isnot [int] -and $Value -isnot [long]) -or
        $Value -lt [int]::MinValue -or $Value -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('Privacy value must be an integer in the signed DWORD range.')
    }
    return [int]$Value
}

function Assert-UindosPrivacyContextObservations {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    # This helper accepts only collected observations so the fail-closed policy
    # can be tested without Windows or registry access.
    if ($Context.elevated -isnot [bool]) {
        throw 'Privacy Apply/Undo elevation state is unknown; refusing to continue.'
    }
    if (-not $Context.elevated) {
        throw 'Run privacy Apply/Undo from a temporarily elevated PowerShell in the desktop user session; no elevation was attempted.'
    }
    if (($Context.sessionId -isnot [int] -and $Context.sessionId -isnot [long]) -or
        $Context.sessionId -lt 0 -or $Context.currentSid -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Context.currentSid)) {
        throw 'Privacy desktop identity or session is unknown; refusing to continue.'
    }

    $explorers = @($Context.explorerProcesses)
    $sameSession = @($explorers | Where-Object {
        ($_.sessionId -is [int] -or $_.sessionId -is [long]) -and
        $_.sessionId -eq $Context.sessionId
    })
    if ($sameSession.Count -eq 0) {
        throw 'Privacy Apply/Undo requires Explorer in the current session; no matching process was found.'
    }

    $matchingOwner = $false
    foreach ($process in $sameSession) {
        if (($process.returnValue -isnot [int] -and $process.returnValue -isnot [long]) -or
            $process.returnValue -ne 0 -or $process.sid -isnot [string] -or
            [string]::IsNullOrWhiteSpace($process.sid)) {
            throw 'Explorer owner probe failed or returned unknown data; refusing to continue.'
        }
        if ($process.sid -ceq $Context.currentSid) { $matchingOwner = $true }
    }
    if (-not $matchingOwner) {
        throw 'Privacy Apply/Undo requires an elevated process for the same user and session as Explorer.'
    }
}

function Assert-UindosPrivacyContext {
    [CmdletBinding()]
    param([AllowNull()]$Context)

    if (-not $PSBoundParameters.ContainsKey('Context')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Privacy changes require a Windows desktop session.')
        }
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = [Security.Principal.WindowsPrincipal]::new($identity)
            $sessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
            $explorerProcesses = @()
            foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)) {
                if ($null -eq $process.SessionId) {
                    throw 'Explorer session probe returned no session ID.'
                }
                if ([long]$process.SessionId -ne [long]$sessionId) { continue }
                $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
                if ($null -eq $owner -or $null -eq $owner.ReturnValue) {
                    throw 'Explorer owner probe returned no status.'
                }
                $explorerProcesses += [pscustomobject]@{
                    sessionId = [long]$process.SessionId
                    returnValue = [long]$owner.ReturnValue
                    sid = if ($owner.ReturnValue -eq 0) { [string]$owner.Sid } else { $null }
                }
            }
            $Context = [pscustomobject]@{
                elevated = [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                sessionId = [long]$sessionId
                currentSid = [string]$identity.User.Value
                explorerProcesses = @($explorerProcesses)
            }
        }
        catch {
            throw "Privacy desktop context probe failed; refusing to continue. $($_.Exception.Message)"
        }
    }
    Assert-UindosPrivacyContextObservations -Context $Context
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
            if ($Kind -cne 'DWord') {
                throw 'Privacy adapter only writes DWORD integer values.'
            }
            $safeValue = ConvertTo-UindosPrivacyDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $safeValue -Force -ErrorAction Stop | Out-Null
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
