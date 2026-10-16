# Read-only, mockable system inventory. No write operations.
. (Join-Path $PSScriptRoot 'Probes.ps1')

function Get-UindosDefaultProviders {
    return [ordered]@{
        os = { Get-UindosOsInfo }
        appxCurrentUser = { Get-UindosAppxCurrentUser }
        appxAllUsers = { Get-UindosAppxAllUsers }
        appxProvisioned = { Get-UindosProvisionedAppx }
        win32Programs = { Get-UindosWin32Programs }
        privacyPolicyValues = { Get-UindosPrivacyPolicies }
        selectedServices = { Get-UindosServiceStatus }
        defender = { Get-UindosDefenderStatus }
        firewall = { Get-UindosFirewallStatus }
        bitLockerSystemVolume = { Get-UindosBitLockerStatus }
        secureBoot = { Get-UindosSecureBootStatus }
        systemDisk = { Get-UindosSystemDisk }
        recentHotfixes = { Get-UindosRecentHotfixes }
    }
}

function Invoke-UindosReadOnlyProbe {
    param([Parameter(Mandatory)][string]$Name, [AllowNull()][scriptblock]$Provider)

    if ($null -eq $Provider) {
        return [pscustomobject]@{ status = 'not-collected'; data = @(); reason = 'No provider specified.' }
    }

    try {
        $data = @(& $Provider)
        return [pscustomobject]@{ status = 'ok'; data = $data; reason = $null }
    }
    catch [System.NotSupportedException] {
        return [pscustomobject]@{ status = 'unsupported'; data = @(); reason = $_.Exception.Message }
    }
    catch [System.UnauthorizedAccessException] {
        return [pscustomobject]@{ status = 'unsupported'; data = @(); reason = 'Access denied. This probe may require elevation.' }
    }
    catch [System.Security.SecurityException] {
        return [pscustomobject]@{ status = 'unsupported'; data = @(); reason = 'Access denied. This probe may require elevation.' }
    }
    catch {
        # Do not include exception details: some errors include profile paths or account IDs.
        return [pscustomobject]@{ status = 'error'; data = @(); reason = "Probe '$Name' failed; inspect locally with explicit troubleshooting." }
    }
}

function Get-UindosBaseline {
    [CmdletBinding()]
    param([AllowNull()][System.Collections.IDictionary]$Providers)

    # Providers override is for isolated tests: no Windows check or default probes run.
    $mockMode = $PSBoundParameters.ContainsKey('Providers')
    if (-not $mockMode) {
        if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows)) {
            throw [System.NotSupportedException]::new('uindos baseline requires Windows unless test providers are injected.')
        }
        $Providers = Get-UindosDefaultProviders
    }

    $probeNames = @(
        'os', 'appxCurrentUser', 'appxAllUsers', 'appxProvisioned',
        'win32Programs', 'privacyPolicyValues', 'selectedServices',
        'defender', 'firewall', 'bitLockerSystemVolume', 'secureBoot',
        'systemDisk', 'recentHotfixes'
    )

    $probes = [ordered]@{}
    foreach ($name in $probeNames) {
        $block = $null
        if ($null -ne $Providers -and $Providers.Contains($name)) {
            $block = $Providers[$name]
        }
        $probes[$name] = Invoke-UindosReadOnlyProbe -Name $name -Provider $block
    }

    return [pscustomobject]@{
        schema = 'uindos.baseline/v1'
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        collection = if ($mockMode) { 'injected-test-providers' } else { 'local-windows-read-only' }
        note = 'Policy values are observations, not proof of effectiveness or privacy guarantees. Omitted fields may require elevation.'
        probes = [pscustomobject]$probes
    }
}
