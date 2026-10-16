# Requires -Version 7.0
<#
.SYNOPSIS
    Preview or deprovision curated consumer/media AppX packages for NEW users.
.DESCRIPTION
    Requires Administrator elevation even for preview. Default is read-only.
    Deprovisioning is not automatically reversible. It does not remove apps
    from existing user profiles; use uindos-debloat.ps1 for current user.
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$AcceptDeprovisioning
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\ProvisionedApps.ps1')

try {
    $provider = New-UindosProvisionedAppxProvider
    if ($Apply) {
        if (-not $AcceptDeprovisioning) {
            throw 'Apply requires -AcceptDeprovisioning.'
        }
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA unavailable; refusing changes without a journal.'
        }
        $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\app-deprovision-v1'
        $result = Invoke-UindosProvisionedAppRemoval -Provider $provider -JournalDirectory $journal -Apply -AcceptDeprovisioning
        ConvertTo-Json -InputObject $result -Depth 12
        if ($result.status -eq 'needs-review') { exit 2 }
    }
    elseif ($AcceptDeprovisioning) {
        throw '-AcceptDeprovisioning only applies with -Apply.'
    }
    else {
        $plan = Get-UindosProvisionedAppPlan -Provider $provider
        ConvertTo-Json -InputObject $plan -Depth 12
    }
}
catch {
    Write-Error ('uindos deprovision: ' + $_.Exception.Message)
    exit 1
}
