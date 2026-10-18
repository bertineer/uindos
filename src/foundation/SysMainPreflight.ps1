# Read-only, fixed-target SysMain state preflight. No service-control write API is used.

function Get-UindosSysMainDefaultProviders {
    [ordered]@{
        os = { Get-UindosSysMainOsInfo }
        service = { Get-UindosSysMainServiceInfo }
        registry = { Get-UindosSysMainRegistryInfo }
        relationships = { Get-UindosSysMainRelationships }
    }
}

function Get-UindosSysMainOsInfo {
    $current = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    [pscustomobject]@{
        editionId = [string]$current.EditionID
        build = [string]$current.CurrentBuildNumber
        updateRevision = $current.UBR
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    }
}

function Get-UindosSysMainServiceInfo {
    $rows = @(Get-CimInstance -ClassName Win32_Service -Filter "Name='SysMain'" -ErrorAction Stop)
    if ($rows.Count -eq 0) { return [pscustomobject]@{ found = $false } }
    if ($rows.Count -ne 1) { throw [IO.InvalidDataException]::new('SysMain service query returned an unexpected number of rows.') }
    $row = $rows[0]
    [pscustomobject]@{
        found = $true
        name = [string]$row.Name
        state = [string]$row.State
        startMode = [string]$row.StartMode
        processId = $row.ProcessId
    }
}

function Get-UindosSysMainRegistryValue {
    param([Parameter(Mandatory)][Microsoft.Win32.RegistryKey]$Key, [Parameter(Mandatory)][string]$Name)
    $exists = @($Key.GetValueNames() | Where-Object { [string]::Equals($_, $Name, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if (-not $exists) { return [pscustomobject]@{ exists = $false; kind = $null; value = $null } }
    $kind = $Key.GetValueKind($Name)
    $value = $Key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    [pscustomobject]@{ exists = $true; kind = $kind.ToString(); value = $value }
}

function Get-UindosSysMainRegistryInfo {
    $base = $null
    $key = $null
    try {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.OpenSubKey('SYSTEM\CurrentControlSet\Services\SysMain', $false)
        if ($null -eq $key) { return [pscustomobject]@{ keyExists = $false } }
        [pscustomobject]@{
            keyExists = $true
            start = Get-UindosSysMainRegistryValue -Key $key -Name 'Start'
            delayedAutoStart = Get-UindosSysMainRegistryValue -Key $key -Name 'DelayedAutoStart'
        }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $base) { $base.Dispose() }
    }
}

function Get-UindosSysMainRelationships {
    $service = Get-Service -Name 'SysMain' -ErrorAction Stop
    [pscustomobject]@{
        dependencies = [string[]]@($service.ServicesDependedOn | ForEach-Object { [string]$_.Name })
        dependents = [string[]]@($service.DependentServices | ForEach-Object { [string]$_.Name })
    }
}

function Invoke-UindosSysMainProbe {
    param([Parameter(Mandatory)][scriptblock]$Provider)
    try { return [pscustomobject]@{ status = 'ok'; data = (& $Provider) } }
    catch [System.NotSupportedException] { return [pscustomobject]@{ status = 'unsupported'; data = $null } }
    catch [System.UnauthorizedAccessException] { return [pscustomobject]@{ status = 'access-denied'; data = $null } }
    catch [System.Security.SecurityException] { return [pscustomobject]@{ status = 'access-denied'; data = $null } }
    catch { return [pscustomobject]@{ status = 'error'; data = $null } }
}

function ConvertTo-UindosSysMainProbeError {
    param([Parameter(Mandatory)][string]$Status)
    [pscustomobject]@{ status = $Status; data = $null }
}

function Test-UindosSysMainStringArray {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or $Value -isnot [array]) { return $false }
    foreach ($item in $Value) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item) -or $item -notmatch '^[A-Za-z0-9_.$-]+$') { return $false }
    }
    return $true
}

function Test-UindosSysMainDWordNumber {
    param([AllowNull()][object]$Value)
    return ($Value -is [int] -or $Value -is [uint32] -or $Value -is [long] -or $Value -is [uint64]) -and
        $Value -ge 0 -and $Value -le [uint32]::MaxValue
}

function Get-UindosSysMainPreflight {
    [CmdletBinding()]
    param(
        [Parameter()][System.Collections.IDictionary]$Providers,
        [Parameter()][switch]$TestNonWindows
    )

    $injected = $PSBoundParameters.ContainsKey('Providers')
    $windowsPlatform = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)
    if ($TestNonWindows -or (-not $injected -and -not $windowsPlatform)) {
        return [pscustomobject]@{
            schema = 'uindos.sysmain-preflight/v1'
            timestampUtc = [DateTime]::UtcNow.ToString('o')
            collection = 'unsupported'
            platform = [pscustomobject]@{ status = 'unsupported'; edition = $null; build = $null; architecture = $null }
            probes = [pscustomobject]@{ os = 'unsupported'; service = 'unsupported'; registry = 'unsupported'; relationships = 'unsupported' }
            service = $null; registry = $null; relationships = $null
            consistency = 'not-assessed'
            limitations = @('Read-only state observation only; this report does not establish safety, readiness, or authorization to change SysMain.')
        }
    }
    if (-not $injected) { $Providers = Get-UindosSysMainDefaultProviders }

    $names = @('os','service','registry','relationships')
    $probes = [ordered]@{}
    foreach ($name in $names) {
        if ($null -eq $Providers -or -not $Providers.Contains($name) -or $Providers[$name] -isnot [scriptblock]) {
            $probes[$name] = ConvertTo-UindosSysMainProbeError -Status 'not-collected'
        } else {
            $probes[$name] = Invoke-UindosSysMainProbe -Provider $Providers[$name]
        }
    }

    # Validate OS identity and retain exact build plus UBR without host-specific data.
    $platformStatus = 'unknown'
    $platform = [ordered]@{ status = 'unknown'; edition = $null; build = $null; architecture = $null }
    if ($probes.os.status -eq 'ok') {
        $os = $probes.os.data
        [long]$buildNumber = 0
        [long]$ubr = 0
        if ($null -eq $os -or [string]::IsNullOrWhiteSpace([string]$os.editionId) -or
            -not [long]::TryParse([string]$os.build, [ref]$buildNumber) -or $buildNumber -lt 0 -or
            -not [long]::TryParse([string]$os.updateRevision, [ref]$ubr) -or $ubr -lt 0 -or
            [string]$os.architecture -notin @('X64','Arm64')) {
            $probes.os = ConvertTo-UindosSysMainProbeError -Status 'error'
            $platformStatus = 'error'
            $platform = [ordered]@{ status = 'error'; edition = $null; build = $null; architecture = $null }
        } elseif ([string]$os.editionId -notin @('Professional','ProfessionalN') -or $buildNumber -lt 22000) {
            $platformStatus = 'unsupported'
            $platform = [ordered]@{
                status = 'unsupported'
                edition = 'unsupported-edition-or-build'
                build = [pscustomobject]@{ number = $buildNumber; updateRevision = $ubr; full = "$buildNumber.$ubr" }
                architecture = [string]$os.architecture
            }
        } else {
            $platformStatus = 'supported'
            $platform = [ordered]@{
                status = 'supported'
                edition = if ([string]$os.editionId -ceq 'ProfessionalN') { 'Windows 11 Pro N' } else { 'Windows 11 Pro' }
                build = [pscustomobject]@{ number = $buildNumber; updateRevision = $ubr; full = "$buildNumber.$ubr" }
                architecture = [string]$os.architecture
            }
        }
    } elseif ($probes.os.status -in @('unsupported','error','access-denied')) {
        $platformStatus = $probes.os.status
        $platform.status = $platformStatus
    }

    # Service query must identify exactly SysMain and contain only expected fields.
    $service = $null
    if ($probes.service.status -eq 'ok') {
        $item = $probes.service.data
        if ($null -eq $item -or $item.found -isnot [bool]) {
            $probes.service = ConvertTo-UindosSysMainProbeError -Status 'error'
        } elseif (-not $item.found) {
            $probes.service = ConvertTo-UindosSysMainProbeError -Status 'not-found'
        } elseif ([string]$item.name -cne 'SysMain' -or
            [string]$item.state -notin @('Running','Stopped','Paused','Start Pending','Stop Pending','Continue Pending','Pause Pending') -or
            [string]$item.startMode -notin @('Auto','Manual','Disabled','Boot','System') -or
            -not (Test-UindosSysMainDWordNumber $item.processId)) {
            $probes.service = ConvertTo-UindosSysMainProbeError -Status 'error'
        } else {
            $service = [pscustomobject]@{ name = 'SysMain'; state = [string]$item.state; startMode = [string]$item.startMode; processId = [long]$item.processId }
        }
    }

    # Exact typed service values: preserve absent delayed-start as absent, never coerce it to zero.
    $registry = $null
    if ($probes.registry.status -eq 'ok') {
        $item = $probes.registry.data
        $valid = $null -ne $item -and $item.keyExists -is [bool] -and $item.keyExists -and
            $null -ne $item.start -and $null -ne $item.delayedAutoStart
        foreach ($valueName in @('start','delayedAutoStart')) {
            $value = if ($null -ne $item) { $item.$valueName } else { $null }
            if ($null -eq $value -or $value.exists -isnot [bool]) { $valid = $false; continue }
            if ($value.exists) {
                if ([string]$value.kind -cne 'DWord' -or -not (Test-UindosSysMainDWordNumber $value.value)) { $valid = $false }
            } elseif ($null -ne $value.kind -or $null -ne $value.value) { $valid = $false }
        }
        if ($valid) {
            $startValue = [long]$item.start.value
            $delayed = $item.delayedAutoStart
            $valid = $item.start.exists -and $startValue -in @(0,1,2,3,4) -and
                (-not $delayed.exists -or [long]$delayed.value -in @(0,1))
        }
        if (-not $valid) {
            $probes.registry = ConvertTo-UindosSysMainProbeError -Status 'error'
        } else {
            $registry = [pscustomobject]@{
                start = [pscustomobject]@{ exists = $true; kind = 'DWord'; value = $startValue }
                delayedAutoStart = [pscustomobject]@{
                    exists = [bool]$delayed.exists
                    kind = if ($delayed.exists) { 'DWord' } else { $null }
                    value = if ($delayed.exists) { [long]$delayed.value } else { $null }
                }
            }
        }
    }

    $relationships = $null
    if ($probes.relationships.status -eq 'ok') {
        $item = $probes.relationships.data
        if ($null -eq $item -or -not (Test-UindosSysMainStringArray $item.dependencies) -or -not (Test-UindosSysMainStringArray $item.dependents)) {
            $probes.relationships = ConvertTo-UindosSysMainProbeError -Status 'error'
        } else {
            $relationships = [pscustomobject]@{
                dependencies = [string[]]@($item.dependencies | Sort-Object -Unique)
                dependents = [string[]]@($item.dependents | Sort-Object -Unique)
            }
        }
    }

    $consistency = 'unknown'
    if ($null -ne $service -and $null -ne $registry) {
        $expectedStart = @{ Boot=0; System=1; Auto=2; Manual=3; Disabled=4 }[$service.startMode]
        $consistent = ([long]$registry.start.value -eq $expectedStart) -and
            (-not ($registry.delayedAutoStart.exists -and $registry.delayedAutoStart.value -eq 1) -or $expectedStart -eq 2)
        $consistency = if ($consistent) { 'consistent' } else { 'inconsistent' }
        if (-not $consistent) {
            $probes.service = ConvertTo-UindosSysMainProbeError -Status 'error'
            $probes.registry = ConvertTo-UindosSysMainProbeError -Status 'error'
        }
    }

    $allOk = @($names | Where-Object { $probes[$_].status -eq 'ok' }).Count -eq $names.Count
    $collection = if ($platformStatus -eq 'unsupported') { 'unsupported' }
        elseif ($platformStatus -ne 'supported') { 'error' }
        elseif ($consistency -eq 'inconsistent') { 'error' }
        elseif ($allOk -and $null -ne $service -and $null -ne $registry -and $null -ne $relationships) { 'complete' }
        elseif (@($names | Where-Object { $probes[$_].status -in @('error','access-denied','not-collected') }).Count -gt 0) { 'partial' }
        else { 'incomplete' }

    [pscustomobject]@{
        schema = 'uindos.sysmain-preflight/v1'
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        collection = if ($injected) { "injected-test-providers:$collection" } else { $collection }
        platform = [pscustomobject]$platform
        probes = [pscustomobject]@{ os = $probes.os.status; service = $probes.service.status; registry = $probes.registry.status; relationships = $probes.relationships.status }
        service = $service
        registry = $registry
        relationships = $relationships
        consistency = $consistency
        limitations = @('Read-only state observation only; no safety, readiness, or authorization to change SysMain is implied.','Build applicability is limited to Windows 11 Pro/Pro N x64 or ARM64, build 22000 or later; only build 26300.9711 is recorded as tested in the source VM.','No account, device name, command line, binary path, service SID, or raw provider error is included.')
    }
}
