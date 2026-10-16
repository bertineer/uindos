# PowerShell 7 mock tests: do not touch AppX, registry or Windows.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\ConsumerApps.ps1')

function Assert-Test {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$os = [pscustomobject]@{ editionId='Professional';build='26100';architecture='X64' }
foreach ($bad in @(
    [pscustomobject]@{ editionId='Core';build='26100';architecture='X64' },
    [pscustomobject]@{ editionId='Professional';build='19045';architecture='X64' },
    [pscustomobject]@{ editionId='Enterprise';build='26100';architecture='X64' }
)) {
    $blocked = $false
    try { [void](Assert-UindosSupportedAppRemovalOs -OsInfo $bad) }
    catch [System.NotSupportedException] { $blocked = $true }
    Assert-Test $blocked 'Unsupported Windows edition/build blocked'
}

$names = @(Get-UindosConsumerAppNames)
Assert-Test ($names.Count -eq 5) 'Five curated packages'
Assert-Test ($names -ccontains 'Microsoft.Copilot') 'Copilot included'
foreach ($protected in @('Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.GamingApp','Microsoft.Edge','Microsoft.WebView2','Microsoft.XboxGamingOverlay')) {
    Assert-Test ($names -cnotcontains $protected) "Protected $protected excluded"
}
$publisher = '8wekyb3d8bbwe'
function New-Fixture {
    param([string]$Name, [string]$Publisher = '8wekyb3d8bbwe', [bool]$Framework = $false)
    [pscustomobject]@{
        Name=$Name;Version='1.0.0.0';PublisherId=$Publisher
        PackageFullName=($Name + '_1.0.0.0_x64__8wekyb3d8bbwe')
        IsFramework=$Framework;IsResourcePackage=$false;NonRemovable=$false
    }
}
$script:packages=@{}
$script:removed=0
$script:failOn=$null
$provider=@{
    Read = {
        param([string]$Name)
        if ($script:packages.ContainsKey($Name)) { return $script:packages[$Name] }
        return @()
    }
    Remove = {
        param([string]$Name,[string]$PackageFullName)
        if ($script:failOn -eq $Name) { throw 'simulated AppX failure' }
        if (-not $script:packages.ContainsKey($Name)) { throw 'No fixture' }
        if ($script:packages[$Name].PackageFullName -cne $PackageFullName) { throw 'Package drift' }
        $script:packages.Remove($Name)
        $script:removed++
    }
}
$script:packages['Microsoft.Copilot']=New-Fixture 'Microsoft.Copilot'
$script:packages['Microsoft.BingWeather']=New-Fixture 'Microsoft.BingWeather'
$journal=Join-Path ([IO.Path]::GetTempPath()) ('uindos-appx-mock-'+[Guid]::NewGuid().ToString('N'))

try {
    $p=Get-UindosConsumerAppPlan -Provider $provider -OsInfo $os
    Assert-Test ($p.mode -eq 'read-only' -and $p.removalCount -eq 2) 'Preview two present packages'
    Assert-Test ($p.entries.Count -eq 5 -and $p.blockedCount -eq 0) 'Full curated inventory'
    Assert-Test (-not (Test-Path $journal) -and $script:removed -eq 0) 'Preview no file writes or removal'

    $blocked=$false
    try { [void](Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -Apply -OsInfo $os) }
    catch { $blocked=$true }
    Assert-Test ($blocked -and $script:removed -eq 0) 'No removal without app-data-loss acceptance'
    $blocked=$false
    try { [void](Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -AcceptAppDataLoss -OsInfo $os) }
    catch { $blocked=$true }
    Assert-Test $blocked 'No removal without explicit apply'

    $result=Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -Apply -AcceptAppDataLoss -OsInfo $os
    Assert-Test ($result.status -eq 'completed' -and $result.removed -eq 2) 'Selected current-user apps removed'
    Assert-Test ($script:removed -eq 2 -and $script:packages.Count -eq 0) 'Exact package inventory removed'
    $saved=Get-Content -LiteralPath (Join-Path $journal "$($result.journalId).json") -Raw | ConvertFrom-Json
    Assert-Test ($saved.status -eq 'completed' -and $saved.noAutomaticRollback) 'Journal explicitly records irreversibility'
    Assert-Test ($saved.items.Count -eq 2) 'Only selected installed app identities journaled'

    $repeat=Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -Apply -AcceptAppDataLoss -OsInfo $os
    Assert-Test ($repeat.status -eq 'unchanged' -and $script:removed -eq 2) 'Repeated apply is no-op'

    $script:packages['Microsoft.Copilot']=New-Fixture -Name 'Microsoft.Copilot' -Publisher 'unrecognized'
    $suspect=Get-UindosConsumerAppPlan -Provider $provider -OsInfo $os
    Assert-Test ($suspect.blockedCount -eq 1) 'Unrecognized publisher blocked'
    $blocked=$false
    try { [void](Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -Apply -AcceptAppDataLoss -OsInfo $os) }
    catch { $blocked=$true }
    Assert-Test ($blocked -and $script:removed -eq 2) 'Blocked app prevents removal'

    $script:packages['Microsoft.Copilot']=New-Fixture -Name 'Microsoft.Copilot'
    $script:packages['Microsoft.BingNews']=New-Fixture -Name 'Microsoft.BingNews'
    $script:failOn='Microsoft.BingNews'
    $partial=Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -Apply -AcceptAppDataLoss -OsInfo $os
    Assert-Test ($partial.status -eq 'needs-review') 'Failed removal not reported successful'
    $partialJournal=Get-Content -LiteralPath (Join-Path $journal "$($partial.journalId).json") -Raw | ConvertFrom-Json
    Assert-Test ($partialJournal.status -eq 'needs-review') 'Partial failure persisted'
    Assert-Test ($partialJournal.items.Count -eq 2) 'Failed package retained in journal'
    Assert-Test ($script:packages.ContainsKey('Microsoft.BingNews')) 'No fake rollback for failed AppX'
    $script:failOn=$null

    Assert-Test (-not (Test-UindosAppxIdentity 'Microsoft.Edge' 'Microsoft.Edge_1.0.0.0_x64__8wekyb3d8bbwe')) 'Outside allowlist identity denied'
    Assert-Test (-not (Test-UindosAppxIdentity 'Microsoft.Copilot' 'Microsoft.Copilot_1.0.0.0_x64__untrusted')) 'Unknown publisher identity denied'
    Assert-Test (Test-UindosAppxIdentity 'Microsoft.Copilot' 'Microsoft.Copilot_1.0.0.0_x64__8wekyb3d8bbwe') 'Expected package identity recognized'
    Write-Output 'PASS: AppX mock planning, identity protections, explicit consent, journal and partial failure'
}
finally {
    if (Test-Path -LiteralPath $journal) { Remove-Item -LiteralPath $journal -Force -Recurse -ErrorAction SilentlyContinue }
}
