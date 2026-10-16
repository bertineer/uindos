# Hosted Windows runner integration: interrogates AppX read-only, never uninstalls.
$ErrorActionPreference='Stop'
if (-not $IsWindows) { throw 'Windows required.' }
. (Join-Path $PSScriptRoot '..\src\foundation\ConsumerApps.ps1')
$provider=New-UindosAppxProvider
# A hosted GitHub runner may be Windows Server, so inject the supported OS
# fixture ONLY in this read-only test; never call -Apply in this script.
$os=[pscustomobject]@{editionId='Professional';build='26100';architecture='X64'}
$p=Get-UindosConsumerAppPlan -Provider $provider -OsInfo $os
if ($p.schema -ne 'uindos.app-removal-plan/v1' -or $p.entries.Count -ne 21) {
    throw 'AppX plan schema or fixed list invalid.'
}
foreach ($item in $p.entries) {
    if ($item.status -notin @('ready','absent','blocked')) { throw 'Unexpected package state.' }
}
Write-Output 'PASS: live AppX read-only discovery completed; no installed package identities printed'
