# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo current-user taskbar visibility preferences.
.DESCRIPTION
    Hides taskbar Search and Task View. Widgets are managed separately by
    uindos-widgets because their supported control is a device policy.
    Does NOT remove installed apps or change pinned app layouts or Windows Search service.
    Sign out/in if Explorer has not reflected the new preferences.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Taskbar.ps1')

try {
    $adapter = New-UindosTaskbarAdapter
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA is unavailable. Refusing to proceed without journal directory.'
    }
    $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\taskbar-v1'
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    else {
        $actions = @(Get-UindosTaskbarActions)
        if ($PSCmdlet.ParameterSetName -eq 'Apply') {
            $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
        }
        else {
            $response = Get-UindosPlan -Actions $actions -Adapter $adapter
        }
    }
    $response | Add-Member -NotePropertyName widgetsNote -NotePropertyValue 'Widgets are managed separately with bin/uindos-widgets.ps1.' -Force
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
}
catch {
    Write-Error ('uindos taskbar: ' + $_.Exception.Message)
    exit 1
}
