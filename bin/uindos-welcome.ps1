# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo current-user welcome visibility preferences.
.DESCRIPTION
    Disables three current-user notifications/setup suggestions. Does not
    remove initial Windows setup, disable updates or silence security alerts.
    Sign out/in if Settings has not refreshed these user preferences.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Welcome.ps1')

try {
    $adapter = New-UindosWelcomeAdapter
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable. Refusing to proceed without journal directory.'
    }
    $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\welcome-v1'
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    else {
        $actions = @(Get-UindosWelcomeActions)
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
    Write-Error ('uindos welcome: ' + $_.Exception.Message)
    exit 1
}
