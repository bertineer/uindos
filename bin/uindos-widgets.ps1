# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo the supported Windows 11 Pro Widgets policy.
.DESCRIPTION
    Plan is read-only and works without elevation. Apply and Undo require an
    already elevated PowerShell process; this command never auto-elevates.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Widgets.ps1')

try {
    $adapter = New-UindosWidgetsAdapter
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable. Refusing to proceed without journal directory.'
    }
    $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\widgets-v1'
    if ($PSCmdlet.ParameterSetName -ne 'Plan' -and -not (Test-UindosAdministrator)) {
        throw 'Widgets policy Apply and Undo require an already elevated PowerShell process; no elevation was attempted.'
    }
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    else {
        $actions = @(Get-UindosWidgetsActions)
        if ($PSCmdlet.ParameterSetName -eq 'Apply') {
            $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
        }
        else {
            $response = Get-UindosPlan -Actions $actions -Adapter $adapter
        }
    }
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
}
catch {
    Write-Error ('uindos widgets: ' + $_.Exception.Message)
    exit 1
}
