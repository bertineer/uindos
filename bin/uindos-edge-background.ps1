# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo the two supported Microsoft Edge background policies.
.DESCRIPTION
    Plan is read-only and does not need elevation or a journal. Apply and Undo
    require an already elevated PowerShell process; this command never self-elevates.
    Edge Update, WebView2, services, and running processes are not modified.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo,
    [Parameter()][string]$JournalDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\EdgeBackground.ps1')

try {
    # Preview is independent of LOCALAPPDATA and never creates a journal.
    if ($PSCmdlet.ParameterSetName -ne 'Plan') {
        Assert-UindosEdgeBackgroundWriteAuthorization -IsAdministrator (Test-UindosEdgeBackgroundAdministrator)
    }
    $adapter = New-UindosEdgeBackgroundAdapter
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        $journal = Get-UindosEdgeBackgroundJournalDirectory -JournalDirectory $JournalDirectory `
            -HasOverride ($PSBoundParameters.ContainsKey('JournalDirectory')) -LocalAppData $env:LOCALAPPDATA
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Apply') {
        $actions = @(Get-UindosEdgeBackgroundActions)
        $journal = Get-UindosEdgeBackgroundJournalDirectory -JournalDirectory $JournalDirectory `
            -HasOverride ($PSBoundParameters.ContainsKey('JournalDirectory')) -LocalAppData $env:LOCALAPPDATA
        $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
    }
    else {
        $actions = @(Get-UindosEdgeBackgroundActions)
        $response = Get-UindosPlan -Actions $actions -Adapter $adapter
    }
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
}
catch {
    Write-Error ('uindos edge-background: ' + $_.Exception.Message)
    exit 1
}
