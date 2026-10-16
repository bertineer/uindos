# Dependency-free smoke tests; injected providers do not invoke Windows APIs.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Baseline.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$script:executed = 0
$providers = [ordered]@{
    os = {
        $script:executed++
        [pscustomobject]@{ editionId = 'Professional'; build = '26100' }
    }
    appxCurrentUser = {
        $script:executed++
        [pscustomobject]@{ name = 'Microsoft.Copilot'; version = '1.0' }
    }
    appxProvisioned = {
        $script:executed++
        throw [System.NotSupportedException]::new('Needs elevation.')
    }
    defender = {
        $script:executed++
        throw [System.InvalidOperationException]::new('Private detail C:\Users\Example')
    }
    firewall = {
        $script:executed++
        @()
    }
}

$report = Get-UindosBaseline -Providers $providers
Assert-Test ($report.schema -eq 'uindos.baseline/v1') 'schema'
Assert-Test ($report.collection -eq 'injected-test-providers') 'mock mode'
Assert-Test ($script:executed -eq 5) 'only injected providers executed'
Assert-Test ($report.probes.os.status -eq 'ok') 'OS probe status'
Assert-Test ($report.probes.os.data.Count -eq 1) 'single item is an array'
Assert-Test ($report.probes.os.data[0].build -eq '26100') 'OS details'
Assert-Test ($report.probes.appxCurrentUser.data[0].name -eq 'Microsoft.Copilot') 'AppX details'
Assert-Test ($report.probes.appxProvisioned.status -eq 'unsupported') 'unsupported status'
Assert-Test ($report.probes.defender.status -eq 'error') 'unexpected error status'
Assert-Test ($report.probes.firewall.status -eq 'ok') 'empty result success'
Assert-Test ($report.probes.firewall.data.Count -eq 0) 'empty array'
Assert-Test ($report.probes.selectedServices.status -eq 'not-collected') 'absent test provider'
Assert-Test (-not ($report.probes.defender.reason -match 'Users|Example|C:')) 'no raw exception paths'

$json = ConvertTo-Json -InputObject $report -Depth 12
$parsed = ConvertFrom-Json -InputObject $json
Assert-Test ($parsed.schema -eq 'uindos.baseline/v1') 'JSON schema roundtrip'
Assert-Test ($parsed.probes.os.data[0].build -eq '26100') 'JSON data roundtrip'
Assert-Test ($parsed.probes.appxProvisioned.status -eq 'unsupported') 'JSON statuses'
Assert-Test ($report.note -match 'not proof') 'no unsupported telemetry claim'

$source = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\src\core\Probes.ps1') -Raw
foreach ($forbidden in @('Remove-AppxPackage','Remove-AppxProvisionedPackage','Disable-BitLocker','Set-Service','Set-ItemProperty','Invoke-WebRequest','Invoke-RestMethod')) {
    Assert-Test (-not $source.Contains($forbidden)) "State-changing call referenced: $forbidden"
}
Write-Output 'PASS: mock-only uindos baseline smoke tests (Windows probes not exercised)'
