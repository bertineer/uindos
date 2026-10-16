# Cross-platform mock-only provisioning tests. NO Windows servicing calls.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\ProvisionedApps.ps1')

function Assert-Test {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}
$os = [pscustomobject]@{ editionId='Professional'; build='26300'; architecture='X64' }
function New-Row {
    param([string]$Name, [string]$Publisher='8wekyb3d8bbwe')
    [pscustomobject]@{
        name=$Name;version='1.2.3.4'
        packageName=($Name + '_1.2.3.4_neutral_~_' + $Publisher)
    }
}
Assert-Test (Test-UindosProvisionedAppIdentity 'Clipchamp.Clipchamp' '4.5.10920.0' 'Clipchamp.Clipchamp_4.5.10920.0_neutral_~_yxz26nhyzhsrt') 'Clipchamp publisher allowed'
Assert-Test (Test-UindosProvisionedAppIdentity 'MSTeams' '26260.1717.5229.7049' 'MSTeams_26260.1717.5229.7049_x64__8wekyb3d8bbwe') 'No resource-id package allowed'
Assert-Test (-not (Test-UindosProvisionedAppIdentity 'Microsoft.WindowsStore' '1.2.3.4' 'Microsoft.WindowsStore_1.2.3.4_neutral_~_8wekyb3d8bbwe')) 'Store is not eligible'
Assert-Test (-not (Test-UindosProvisionedAppIdentity 'Microsoft.ZuneMusic' '1.2.3.4' 'Microsoft.ZuneMusic_1.2.3.4_neutral_~_unknown')) 'Publisher mismatch rejected'
Assert-Test (-not (Test-UindosProvisionedAppIdentity 'Microsoft.ZuneMusic' '1.2.3.4' 'Microsoft.ZuneMusic_9.9.9.9_neutral_~_8wekyb3d8bbwe')) 'Version mismatch rejected'

$script:rows=@{}
$script:removed=0
$script:failOn=$null
$provider=@{
    Read = {
        @($script:rows.Values)
    }
    Remove = {
        param([string]$Name,[string]$Version,[string]$PackageName)
        if ($Name -eq $script:failOn) { throw 'Mock servicing failed: C:\Users\private' }
        if (-not $script:rows.ContainsKey($Name) -or
            $script:rows[$Name].version -cne $Version -or
            $script:rows[$Name].packageName -cne $PackageName) { throw 'Drift detected' }
        $script:rows.Remove($Name)
        $script:removed++
    }
}
$script:rows['Clipchamp.Clipchamp']=New-Row 'Clipchamp.Clipchamp' 'yxz26nhyzhsrt'
$script:rows['Microsoft.ZuneMusic']=New-Row 'Microsoft.ZuneMusic'
$journal = Join-Path ([IO.Path]::GetTempPath()) ('uindos-deprovision-'+[Guid]::NewGuid().ToString('N'))
try {
    $plan=Get-UindosProvisionedAppPlan -Provider $provider -OsInfo $os
    Assert-Test ($plan.entries.Count -eq 21 -and $plan.removalCount -eq 2 -and $plan.blockedCount -eq 0) 'read-only plan recognizes only curated apps'
    Assert-Test ($plan.scope -eq 'new-users-only' -and $plan.mode -eq 'read-only') 'explicit new-user scope'
    Assert-Test (-not (Test-Path $journal) -and $script:removed -eq 0) 'preview did not mutate anything'

    foreach ($flags in @(@{Apply=$true;AcceptDeprovisioning=$false},@{Apply=$false;AcceptDeprovisioning=$true})) {
        $failed=$false
        try { [void](Invoke-UindosProvisionedAppRemoval -Provider $provider -JournalDirectory $journal -OsInfo $os -Apply:$flags.Apply -AcceptDeprovisioning:$flags.AcceptDeprovisioning) }
        catch { $failed=$true }
        Assert-Test ($failed -and $script:removed -eq 0) 'both consent switches required'
    }
    $result=Invoke-UindosProvisionedAppRemoval -Provider $provider -JournalDirectory $journal -OsInfo $os -Apply -AcceptDeprovisioning
    Assert-Test ($result.status -eq 'completed' -and $result.removed -eq 2) 'deprovision success'
    Assert-Test ($script:rows.Count -eq 0) 'only exact identities removed'
    $saved=Get-Content -LiteralPath (Join-Path $journal "$($result.journalId).json") -Raw | ConvertFrom-Json
    Assert-Test ($saved.scope -eq 'new-users-only' -and $saved.noAutomaticRollback) 'journal scope and irreversibility'
    Assert-Test ($saved.items.Count -eq 2 -and $saved.status -eq 'completed') 'journal entries complete'
    $repeat=Invoke-UindosProvisionedAppRemoval -Provider $provider -JournalDirectory $journal -OsInfo $os -Apply -AcceptDeprovisioning
    Assert-Test ($repeat.status -eq 'unchanged' -and $script:removed -eq 2) 'idempotent repeat'

    $script:rows['Microsoft.ZuneMusic']=New-Row 'Microsoft.ZuneMusic' 'unknown'
    $plan=Get-UindosProvisionedAppPlan -Provider $provider -OsInfo $os
    Assert-Test ($plan.blockedCount -eq 1) 'unexpected publisher is blocked'
    $failed=$false
    try { [void](Invoke-UindosProvisionedAppRemoval -Provider $provider -JournalDirectory $journal -OsInfo $os -Apply -AcceptDeprovisioning) }
    catch { $failed=$true }
    Assert-Test ($failed -and $script:removed -eq 2) 'blocked identity prevents any removal'

    $script:rows['Microsoft.ZuneMusic']=New-Row 'Microsoft.ZuneMusic'
    $script:rows['Microsoft.BingWeather']=New-Row 'Microsoft.BingWeather'
    $script:failOn='Microsoft.ZuneMusic'
    $partial=Invoke-UindosProvisionedAppRemoval -Provider $provider -JournalDirectory $journal -OsInfo $os -Apply -AcceptDeprovisioning
    Assert-Test ($partial.status -eq 'needs-review') 'servicing failure surfaced as needs-review'
    $saved=Get-Content -LiteralPath (Join-Path $journal "$($partial.journalId).json") -Raw | ConvertFrom-Json
    Assert-Test ($saved.status -eq 'needs-review') 'partial journal records failure'
    Assert-Test ((ConvertTo-Json -InputObject $saved -Depth 10) -notmatch 'C:\\Users\\private|Mock servicing failed') 'no raw failure or path leaked'
    $script:failOn=$null

    $unavailable=@{Read={throw 'COM failure'};Remove={throw 'Must never remove'}}
    $failed=$false
    try { [void](Get-UindosProvisionedAppPlan -Provider $unavailable -OsInfo $os) }
    catch { $failed=$true }
    Assert-Test $failed 'read failures never look like no packages'
    Write-Output 'PASS: provisioned-AppX identity allowlist, preview, consent, journaling, idempotence, failures'
}
finally {
    if (Test-Path -LiteralPath $journal) { Remove-Item -LiteralPath $journal -Force -Recurse -ErrorAction SilentlyContinue }
}
