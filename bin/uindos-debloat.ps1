# Requires -Version 7.0
<#
.SYNOPSIS
    Inspect or remove the curated current-user consumer and media AppX applications.
.DESCRIPTION
    Default is a read-only preview. AppX removal can erase app-specific data
    and cannot be automatically undone; requires -Apply -AcceptAppDataLoss.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$AcceptAppDataLoss
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\ConsumerApps.ps1')

try {
    $provider = New-UindosAppxProvider
    if ($Apply) {
        if (-not $AcceptAppDataLoss) {
            throw 'To remove apps, pass both -Apply and -AcceptAppDataLoss.'
        }
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA is unavailable; refusing removal without a journal.'
        }
        $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\app-removal-v1'
        $result = Invoke-UindosConsumerAppRemoval -Provider $provider -JournalDirectory $journal -Apply -AcceptAppDataLoss
        ConvertTo-Json -InputObject $result -Depth 12
        if ($result.status -eq 'needs-review') { exit 2 }
    }
    elseif ($AcceptAppDataLoss) {
        throw '-AcceptAppDataLoss is only valid alongside -Apply.'
    }
    else {
        $plan = Get-UindosConsumerAppPlan -Provider $provider
        ConvertTo-Json -InputObject $plan -Depth 12
    }
}
catch {
    Write-Error ('uindos debloat: ' + $_.Exception.Message)
    exit 1
}
