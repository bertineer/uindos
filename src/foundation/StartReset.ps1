# Fixed, build-gated Start reset policy plus a conservative management guard.
# The action changes policy values only; it does not claim to restore a pin layout.

function Get-UindosStartResetCatalog {
    return @(
        [pscustomobject]@{
            id = 'start.configure-pins-json'
            path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
            name = 'ConfigureStartPinsJSON'
            kind = 'ExpandString'
            value = '{"applyOnce":true,"pinnedList":[]}'
        }
        [pscustomobject]@{
            id = 'start.enable-pins-policy'
            path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'
            name = 'ConfigureStartPins'
            kind = 'DWord'
            value = 1
        }
    )
}

function Get-UindosStartResetActions {
    [CmdletBinding()]
    param([AllowNull()][object]$OsInfo)

    if (-not $PSBoundParameters.ContainsKey('OsInfo')) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('Start reset policy requires the validated Windows build family.')
        }
        $os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $OsInfo = [pscustomobject]@{
            editionId = [string]$os.EditionID
            build = [string]$os.CurrentBuildNumber
            ubr = [string]$os.UBR
            architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
            preview = [bool]($os.PSObject.Properties['PreviewBuild'] -and [int]$os.PreviewBuild -ne 0)
        }
    }

    [long]$build = 0
    [long]$ubr = 0
    $preview = $false
    if ($null -ne $OsInfo.PSObject.Properties['preview']) { $preview = $OsInfo.preview -eq $true }
    if ($null -ne $OsInfo.PSObject.Properties['isPreview']) { $preview = $preview -or $OsInfo.isPreview -eq $true }
    if ($preview -or $null -eq $OsInfo -or
        [string]$OsInfo.editionId -cnotin @('Professional','ProfessionalN') -or
        -not [long]::TryParse([string]$OsInfo.build, [ref]$build) -or $build -ne 26300 -or
        -not [long]::TryParse([string]$OsInfo.ubr, [ref]$ubr) -or $ubr -lt 9711 -or
        [string]$OsInfo.architecture -cnotin @('X64','Arm64')) {
        throw [System.NotSupportedException]::new(
            'Start reset v1 supports only Windows 11 Pro/Pro N x64 or ARM64, build 26300 UBR 9711 or later in the validated build family; preview and other builds are unsupported.'
        )
    }
    return @(Get-UindosStartResetCatalog)
}

function Assert-UindosStartResetAction {
    param([Parameter(Mandatory)]$Action)
    $rule = @(Get-UindosStartResetCatalog | Where-Object { $_.id -ceq [string]$Action.id })
    $valueTypeMatches = $false
    if ($rule.Count -eq 1) {
        if ($rule[0].kind -ceq 'ExpandString') { $valueTypeMatches = $Action.value -is [string] }
        else { $valueTypeMatches = $Action.value -is [int] -or $Action.value -is [long] }
    }
    if ($rule.Count -ne 1 -or $Action.path -isnot [string] -or $Action.name -isnot [string] -or
        $Action.kind -isnot [string] -or $Action.id -isnot [string] -or
        $Action.path -cne $rule[0].path -or $Action.name -cne $rule[0].name -or
        $Action.kind -cne $rule[0].kind -or -not $valueTypeMatches -or
        [string]$Action.value -cne [string]$rule[0].value) {
        throw [System.NotSupportedException]::new('Action differs from the fixed Start reset policy.')
    }
}

function Assert-UindosStartResetTarget {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    $allowed = @(Get-UindosStartResetCatalog | Where-Object {
        [string]::Equals($_.path, $Path, [StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals($_.name, $Name, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($allowed.Count -ne 1) {
        throw [System.NotSupportedException]::new('Registry target is not in the Start reset allowlist.')
    }
}

function ConvertTo-UindosStartResetDword {
    param([Parameter(Mandatory)]$Value)
    if (($Value -isnot [int] -and $Value -isnot [long]) -or
        $Value -lt [int]::MinValue -or $Value -gt [int]::MaxValue) {
        throw [System.NotSupportedException]::new('Start reset prior DWORD must be a signed integer in the DWORD range.')
    }
    return [int]$Value
}

function Assert-UindosStartResetContext {
    [CmdletBinding()]
    param([switch]$RequireElevation)

    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Start reset context checks require Windows.')
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $sessionId = (Get-Process -Id $PID -ErrorAction Stop).SessionId
    $explorers = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop |
        Where-Object { $_.SessionId -eq $sessionId })
    $ownerSids = @(
        foreach ($process in $explorers) {
            $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
            if ($owner.ReturnValue -eq 0 -and $owner.Sid) { [string]$owner.Sid }
        }
    )
    $sameExplorerUser = @($ownerSids | Where-Object { $_ -ceq $identity.User.Value }).Count -gt 0
    if (-not $sameExplorerUser) {
        throw 'Start reset requires the same Windows user and session as Explorer; no elevation was attempted.'
    }
    if ($RequireElevation -and -not $elevated) {
        throw 'Start reset Apply/Undo requires a temporarily elevated process in the Explorer user session; no elevation was attempted.'
    }
    return [pscustomobject]@{
        ownerSid = [string]$identity.User.Value
        privateOwnerSid = [string]$identity.User.Value
        sessionId = [int]$sessionId
        elevated = [bool]$elevated
        sameExplorerUser = [bool]$sameExplorerUser
    }
}

function New-UindosStartResetAdapter {
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
        throw [System.NotSupportedException]::new('Windows Registry is required.')
    }

    return @{
        ValidateAction = { param($Action) Assert-UindosStartResetAction -Action $Action }
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosStartResetTarget -Path $Path -Name $Name
            $rule = @(Get-UindosStartResetCatalog | Where-Object { $_.name -ceq $Name })[0]
            $subKeyPath = $Path.Substring('HKCU:\'.Length)
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $false)
            if ($null -eq $key) { return [pscustomobject]@{ exists=$false; kind=$null; value=$null } }
            try {
                if (@($key.GetValueNames() | Where-Object { [string]::Equals($_, $Name, [StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                    return [pscustomobject]@{ exists=$false; kind=$null; value=$null }
                }
                $actualKind = $key.GetValueKind($Name).ToString()
                if ($actualKind -cne $rule.kind) {
                    throw [System.NotSupportedException]::new('Existing Start reset value has an unexpected registry type; refusing to coerce it.')
                }
                $options = if ($actualKind -ceq 'ExpandString') {
                    [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                } else { [Microsoft.Win32.RegistryValueOptions]::None }
                $value = $key.GetValue($Name, $null, $options)
                if ($actualKind -ceq 'ExpandString' -and $value -isnot [string]) {
                    throw [IO.InvalidDataException]::new('Existing Start JSON policy data is malformed.')
                }
                if ($actualKind -ceq 'DWord' -and $value -isnot [int]) {
                    throw [IO.InvalidDataException]::new('Existing Start enable policy data is malformed.')
                }
                return [pscustomobject]@{ exists=$true; kind=$actualKind; value=$value }
            }
            finally { $key.Dispose() }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosStartResetTarget -Path $Path -Name $Name
            $rule = @(Get-UindosStartResetCatalog | Where-Object { $_.name -ceq $Name })[0]
            if ($Kind -cne $rule.kind) { throw 'Start reset adapter received the wrong registry kind.' }
            if ($Kind -ceq 'ExpandString') {
                if ($Value -isnot [string]) { throw 'Start reset ExpandString requires an actual string value.' }
                $safeValue = $Value
            } else { $safeValue = ConvertTo-UindosStartResetDword -Value $Value }
            $action = [pscustomobject]@{ id=$rule.id; path=$rule.path; name=$rule.name; kind=$rule.kind; value=$rule.value }
            Assert-UindosStartResetAction -Action $action
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Kind -Value $safeValue -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosStartResetTarget -Path $Path -Name $Name
            $subKeyPath = $Path.Substring('HKCU:\'.Length)
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKeyPath, $true)
            if ($null -eq $key) { return }
            try {
                if (@($key.GetValueNames() | Where-Object { [string]::Equals($_, $Name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                    $key.DeleteValue($Name, $false)
                }
            }
            finally { $key.Dispose() }
        }
    }
}

function Test-UindosStartResetGuard {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()][object]$Observations, [switch]$AllowOwnedPolicy)

    $fields = @(
        'domainJoined','cloudJoinPresent','mdmAccountsPresent','userGpoPresent','machineGpoPresent',
        'probeComplete','hkcuLayoutPolicyPresent','hkcuOtherLayoutPolicyPresent','hklmLayoutPolicyPresent','mdmStartPolicyPresent'
    )
    $reasons = [System.Collections.Generic.List[string]]::new()
    $values = @{}
    foreach ($field in $fields) {
        $property = if ($null -eq $Observations) { $null } else { $Observations.PSObject.Properties[$field] }
        if ($null -eq $property -or $property.Value -isnot [bool]) {
            $reasons.Add("unknown-$field")
        } else { $values[$field] = [bool]$property.Value }
    }
    if ($values.ContainsKey('probeComplete') -and -not $values.probeComplete) { $reasons.Add('probe-incomplete') }
    $blockReasons = @{
        domainJoined='domain-joined'; cloudJoinPresent='cloud-join-present'; mdmAccountsPresent='mdm-account-present'
        userGpoPresent='user-gpo-present'; machineGpoPresent='machine-gpo-present'
        hkcuOtherLayoutPolicyPresent='other-user-layout-policy-present'
        hklmLayoutPolicyPresent='machine-layout-policy-present'; mdmStartPolicyPresent='mdm-start-policy-present'
    }
    foreach ($field in $blockReasons.Keys) {
        if ($values.ContainsKey($field) -and $values[$field]) { $reasons.Add($blockReasons[$field]) }
    }
    if ($values.ContainsKey('hkcuLayoutPolicyPresent') -and $values.hkcuLayoutPolicyPresent -and -not $AllowOwnedPolicy) {
        $reasons.Add('hkcu-layout-policy-present')
    }
    return [pscustomobject]@{ allowed=($reasons.Count -eq 0); reasons=@($reasons.ToArray()) }
}

function Get-UindosStartResetGuardData {
    [CmdletBinding()]
    param()

    $observed = [ordered]@{
        domainJoined=$null; cloudJoinPresent=$null; mdmAccountsPresent=$null
        userGpoPresent=$null; machineGpoPresent=$null; probeComplete=$false
        hkcuLayoutPolicyPresent=$null; hkcuOtherLayoutPolicyPresent=$null
        hklmLayoutPolicyPresent=$null; mdmStartPolicyPresent=$null
    }
    if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
        return [pscustomobject]$observed
    }
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($computer.PartOfDomain -isnot [bool]) { throw 'Join-state probe returned an unknown result.' }
        $observed.domainJoined = [bool]$computer.PartOfDomain

        $hasChildren = {
            param([Microsoft.Win32.RegistryHive]$Hive, [string]$SubKey)
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, [Microsoft.Win32.RegistryView]::Default)
            try {
                $key = $base.OpenSubKey($SubKey, $false)
                if ($null -eq $key) { return $false }
                try { return (@($key.GetSubKeyNames()).Count -gt 0) }
                finally { $key.Dispose() }
            } finally { $base.Dispose() }
        }
        $observed.cloudJoinPresent = (& $hasChildren ([Microsoft.Win32.RegistryHive]::LocalMachine) 'SOFTWARE\Microsoft\Windows\CurrentVersion\CloudDomainJoin\JoinInfo') -or
            (& $hasChildren ([Microsoft.Win32.RegistryHive]::CurrentUser) 'Software\Microsoft\Windows NT\CurrentVersion\WorkplaceJoin\JoinInfo')
        $observed.mdmAccountsPresent = & $hasChildren ([Microsoft.Win32.RegistryHive]::LocalMachine) 'SOFTWARE\Microsoft\Provisioning\OMADM\Accounts'

        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $ownedPolicyNames = @('ConfigureStartPins','ConfigureStartPinsJSON')
        $otherPolicyNames = @('LockedStartLayout','StartLayoutFile')
        $policyNames = @($ownedPolicyNames + $otherPolicyNames)
        $hasAnyValue = {
            param([Microsoft.Win32.RegistryHive]$Hive, [string]$SubKey, [string[]]$Names)
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, [Microsoft.Win32.RegistryView]::Default)
            try {
                $key = $base.OpenSubKey($SubKey, $false)
                if ($null -eq $key) { return $false }
                try {
                    $actual = @($key.GetValueNames())
                    return @($Names | Where-Object { $name = $_; @($actual | Where-Object { [string]::Equals($_, $name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0 }).Count -gt 0
                } finally { $key.Dispose() }
            } finally { $base.Dispose() }
        }
        $observed.hkcuLayoutPolicyPresent = (& $hasAnyValue ([Microsoft.Win32.RegistryHive]::CurrentUser) 'Software\Policies\Microsoft\Windows\Explorer' $ownedPolicyNames)
        $observed.hkcuOtherLayoutPolicyPresent = (& $hasAnyValue ([Microsoft.Win32.RegistryHive]::CurrentUser) 'Software\Policies\Microsoft\Windows\Explorer' $otherPolicyNames)
        $observed.hklmLayoutPolicyPresent = (& $hasAnyValue ([Microsoft.Win32.RegistryHive]::LocalMachine) 'SOFTWARE\Policies\Microsoft\Windows\Explorer' $policyNames)
        $mdmPolicyNames = @($policyNames + 'StartLayout')
        $observed.mdmStartPolicyPresent =
            (& $hasAnyValue ([Microsoft.Win32.RegistryHive]::LocalMachine) 'SOFTWARE\Microsoft\PolicyManager\current\device\Start' $mdmPolicyNames) -or
            (& $hasAnyValue ([Microsoft.Win32.RegistryHive]::LocalMachine) "SOFTWARE\Microsoft\PolicyManager\current\$sid\Start" $mdmPolicyNames)

        $windows = [Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)
        $machinePol = Join-Path $windows 'System32\GroupPolicy\Machine\Registry.pol'
        $userPol = Join-Path $windows 'System32\GroupPolicy\User\Registry.pol'
        # File.Exists also returns false on access errors. Distinguish a missing
        # path from an unreadable probe so uncertainty cannot permit mutation.
        $exists = {
            param([string]$LiteralPath)
            try { $null = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop; return $true }
            catch [System.Management.Automation.ItemNotFoundException] { return $false }
        }
        $observed.machineGpoPresent = & $exists $machinePol
        $observed.userGpoPresent = & $exists $userPol
        $gpoUsers = Join-Path $windows 'System32\GroupPolicyUsers'
        if (& $exists $gpoUsers) {
            $userPolicyFiles = @(Get-ChildItem -LiteralPath $gpoUsers -Filter 'Registry.pol' -File -Recurse -Depth 2 -Force -ErrorAction Stop)
            if ($userPolicyFiles.Count -gt 0) { $observed.userGpoPresent = $true }
        }
        $observed.probeComplete = $true
    }
    catch {
        # Keep completed observations for diagnosis, but the guard always blocks incomplete probes.
        $observed.probeComplete = $false
    }
    return [pscustomobject]$observed
}
