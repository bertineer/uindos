# Reversible machine policy for cross-device continuation experiences.
# This sets the documented ADMX EnableCDP participation policy only. It does
# not disable CDP services or promise memory savings.

function Get-UindosSharedExperiencesCatalog {
    @(
        [pscustomobject]@{
            id = 'shared-experiences.disable-continuation'
            path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
            name = 'EnableCdp'
            kind = 'DWord'
            value = 0
        }
    )
}

function Assert-UindosSharedExperiencesAction {
    param([Parameter(Mandatory)]$Action)
    $rule = @(Get-UindosSharedExperiencesCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    if ($rule.Count -ne 1 -or $rule[0].path -cne [string]$Action.path -or
        $rule[0].name -cne [string]$Action.name -or $rule[0].kind -cne [string]$Action.kind -or
        ($Action.value -isnot [int] -and $Action.value -isnot [long]) -or
        [long]$Action.value -ne 0) {
        throw [System.NotSupportedException]::new('Shared-experiences action differs from the single supported EnableCDP policy allowlist.')
    }
}

function Assert-UindosSharedExperiencesTarget {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (@(Get-UindosSharedExperiencesCatalog | Where-Object { $_.path -ceq $Path -and $_.name -ceq $Name }).Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is outside the shared-experiences EnableCDP policy allowlist.')
    }
}

function ConvertTo-UindosSharedExperiencesDword {
    param([Parameter(Mandatory)]$Value)
    # Registry reads produce Int32; JSON journals may deserialize as Int64.
    if (($Value -isnot [int] -and $Value -isnot [long]) -or
        [long]$Value -lt [int]::MinValue -or [long]$Value -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('EnableCdp prior value must be an integer in the signed DWORD range.')
    }
    return [int]$Value
}

function Assert-UindosSharedExperiencesDwordKind {
    param([Parameter(Mandatory)][string]$Kind)
    if ($Kind -cne 'DWord') {
        throw [System.NotSupportedException]::new('Existing EnableCdp policy is not DWORD.')
    }
}

function Get-UindosSharedExperiencesActions {
    [CmdletBinding()]
    param([AllowNull()]$OsInfo)
    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Shared-experiences policy requires Windows 11 Pro.')
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
        throw [System.NotSupportedException]::new('Shared-experiences policy requires Windows 11 Pro/Pro N x64/ARM64, build 22000 or later.')
    }
    return @(Get-UindosSharedExperiencesCatalog)
}

function Test-UindosSharedExperiencesAdministrator {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) { return $false }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-UindosSharedExperiencesWriteAuthorization {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$IsAdministrator)
    if (-not $IsAdministrator) {
        throw 'Shared-experiences policy Apply and Undo require an already elevated PowerShell process; no elevation was attempted.'
    }
}

function Get-UindosSharedExperiencesJournalDirectory {
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
    return Join-Path $LocalAppData 'uindos\transactions\shared-experiences-v1'
}

function Get-UindosSharedExperiencesPolicyManagerSignal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Token)
    try {
        if (-not (Test-Path -LiteralPath $Root -ErrorAction Stop)) { return 'absent' }
        $key = Get-Item -LiteralPath $Root -ErrorAction Stop
        $valueNames = @($key.GetValueNames())
        $subKeyNames = @($key.GetSubKeyNames())
        if (Test-UindosSharedExperiencesPolicyNameSignal -Names $valueNames -Token $Token) { return 'present' }
        if (Test-UindosSharedExperiencesPolicyNameSignal -Names $subKeyNames -Token $Token) { return 'present' }
        return 'absent'
    }
    catch { return 'unknown' }
}

function Test-UindosSharedExperiencesPolicyNameSignal {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Names,
          [Parameter(Mandatory)][string]$Token)
    foreach ($name in $Names) {
        if ([string]::Equals($name, $Token, [StringComparison]::OrdinalIgnoreCase) -or
            $name.StartsWith($Token + '_', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-UindosSharedExperiencesAuthorityProbe {
    # Only inspect machine authority that can conflict with this exact policy.
    # A present Registry.pol is not parsed: fail closed because it may contain
    # this target and registry.pol is a binary policy store.
    $domainJoined = $null
    $registryPol = 'unknown'
    $enableCdp = 'unknown'
    $allowConnectedDevices = 'unknown'
    $enrollmentArtifactRoots = $null
    $providerArtifactRoots = $null
    try {
        $partOfDomain = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain
        if ($partOfDomain -is [bool]) { $domainJoined = $partOfDomain }
    }
    catch { }
    try {
        $registryPolPath = Join-Path $env:WINDIR 'System32\GroupPolicy\Machine\Registry.pol'
        $registryPol = if (Test-Path -LiteralPath $registryPolPath -ErrorAction Stop) { 'present-unparsed' } else { 'absent' }
    }
    catch { }
    $enableCdp = Get-UindosSharedExperiencesPolicyManagerSignal `
        -Root 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\ADMX_GroupPolicy' -Token 'EnableCDP'
    $allowConnectedDevices = Get-UindosSharedExperiencesPolicyManagerSignal `
        -Root 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Connectivity' -Token 'AllowConnectedDevices'
    try {
        $enrollmentArtifactRoots = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop).Count
    }
    catch { }
    try {
        $providerArtifactRoots = @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers' -ErrorAction Stop).Count
    }
    catch { }
    return [pscustomobject]@{
        domainJoined = $domainJoined
        localMachineRegistryPol = $registryPol
        policyManagerEnableCDP = $enableCdp
        policyManagerAllowConnectedDevices = $allowConnectedDevices
        enrollmentArtifactRoots = $enrollmentArtifactRoots
        providerArtifactRoots = $providerArtifactRoots
    }
}

function Get-UindosSharedExperiencesAuthority {
    [CmdletBinding()]
    param([Parameter()][AllowNull()]$Probe)
    if (-not $PSBoundParameters.ContainsKey('Probe')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            $Probe = [pscustomobject]@{
                domainJoined = $null; localMachineRegistryPol = 'unknown'
                policyManagerEnableCDP = 'unknown'; policyManagerAllowConnectedDevices = 'unknown'
                enrollmentArtifactRoots = $null; providerArtifactRoots = $null
            }
        }
        else { $Probe = Get-UindosSharedExperiencesAuthorityProbe }
    }
    if ($null -eq $Probe) { throw 'Authority probe returned no result.' }
    foreach ($field in @('domainJoined','localMachineRegistryPol','policyManagerEnableCDP','policyManagerAllowConnectedDevices')) {
        if ($Probe.PSObject.Properties.Name -cnotcontains $field) {
            throw "Authority probe is missing required field '$field'."
        }
    }
    $classification = 'clear'
    $reason = 'no-conflicting-authority-signals-observed'
    $domainKnown = $Probe.domainJoined -is [bool]
    $unknown = (-not $domainKnown) -or
        ([string]$Probe.localMachineRegistryPol -cnotin @('absent','present-unparsed')) -or
        ([string]$Probe.policyManagerEnableCDP -cnotin @('absent','present')) -or
        ([string]$Probe.policyManagerAllowConnectedDevices -cnotin @('absent','present'))
    $conflict = ($domainKnown -and $Probe.domainJoined) -or
        ([string]$Probe.localMachineRegistryPol -ceq 'present-unparsed') -or
        ([string]$Probe.policyManagerEnableCDP -ceq 'present') -or
        ([string]$Probe.policyManagerAllowConnectedDevices -ceq 'present')
    if ($conflict) {
        $classification = 'blocked'
        $reason = 'management-or-conflicting-policy-signal'
    }
    elseif ($unknown) {
        $classification = 'unknown'
        $reason = 'authority-probe-incomplete-or-unreadable'
    }
    return [pscustomobject]@{
        classification = $classification
        reason = $reason
        signals = [pscustomobject]@{
            domainJoined = $Probe.domainJoined
            localMachineRegistryPol = [string]$Probe.localMachineRegistryPol
            policyManagerEnableCDP = [string]$Probe.policyManagerEnableCDP
            policyManagerAllowConnectedDevices = [string]$Probe.policyManagerAllowConnectedDevices
            enrollmentArtifacts = if ($null -eq $Probe.enrollmentArtifactRoots -and $null -eq $Probe.providerArtifactRoots) { 'unreadable' }
                elseif ([int]$Probe.enrollmentArtifactRoots -gt 0 -or [int]$Probe.providerArtifactRoots -gt 0) { 'present' }
                else { 'none-observed' }
        }
    }
}

function Assert-UindosSharedExperiencesAuthority {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Authority)
    if ([string]$Authority.classification -cne 'clear') {
        throw "Shared-experiences Apply blocked by authority classification '$($Authority.classification)' ($($Authority.reason)); no journal or registry write was attempted."
    }
}

function Invoke-UindosSharedExperiencesApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$Actions,
        [Parameter(Mandatory)][hashtable]$Adapter,
        [Parameter(Mandatory)][string]$JournalDirectory,
        [Parameter(Mandatory)]$Authority
    )
    # Keep this guard adjacent to transaction entry so callers cannot create
    # the journal or write policy after an inconclusive authority probe.
    Assert-UindosSharedExperiencesAuthority -Authority $Authority
    return Invoke-UindosApply -Actions $Actions -Adapter $Adapter -JournalDirectory $JournalDirectory -ConfirmChanges
}

function New-UindosSharedExperiencesAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Shared-experiences policy registry access requires Windows.')
    }
    return @{
        ValidateAction = { param($Action) Assert-UindosSharedExperiencesAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosSharedExperiencesTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
            }
            Assert-UindosSharedExperiencesDwordKind -Kind $key.GetValueKind($Name).ToString()
            return [pscustomobject]@{ exists=$true; kind='DWord'; value=[int]$key.GetValue($Name,$null) }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosSharedExperiencesTarget -Path $Path -Name $Name
            if ($Kind -cne 'DWord') { throw 'Shared-experiences adapter only writes DWORD values.' }
            $safeValue = ConvertTo-UindosSharedExperiencesDword -Value $Value
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $safeValue -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosSharedExperiencesTarget -Path $Path -Name $Name
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
