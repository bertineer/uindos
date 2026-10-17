# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo the supported Windows 11 Pro OneDrive file-sync policy.
.DESCRIPTION
    Preview is read-only and does not need a journal directory or LOCALAPPDATA.
    Apply and Undo require an already elevated PowerShell process; this command
    never auto-elevates. Undo needs only the journal and does not require that
    OneDrive be installed.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo,
    [Parameter()][string]$JournalDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\OneDrivePolicy.ps1')

try {
    $adapter = New-UindosOneDrivePolicyAdapter
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        Assert-UindosOneDrivePolicyWriteAuthorization -IsAdministrator (Test-UindosOneDrivePolicyAdministrator)
        $journal = Get-UindosOneDrivePolicyJournalDirectory -JournalDirectory $JournalDirectory `
            -HasOverride ($PSBoundParameters.ContainsKey('JournalDirectory')) -LocalAppData $env:LOCALAPPDATA
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    else {
        $actions = @(Get-UindosOneDrivePolicyActions)
        if ($PSCmdlet.ParameterSetName -eq 'Plan') {
            $response = Get-UindosPlan -Actions $actions -Adapter $adapter
        }
        else {
            Assert-UindosOneDrivePolicyWriteAuthorization -IsAdministrator (Test-UindosOneDrivePolicyAdministrator)
            $journal = Get-UindosOneDrivePolicyJournalDirectory -JournalDirectory $JournalDirectory `
                -HasOverride ($PSBoundParameters.ContainsKey('JournalDirectory')) -LocalAppData $env:LOCALAPPDATA
            $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
        }
    }
    $response | Add-Member -NotePropertyName behaviorNote -NotePropertyValue 'When Windows enforces this policy, it blocks OneDrive sync and file-storage integration. It does not guarantee OneDrive will not be reinstalled; registry readback alone is not proof of effective behavior.'
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
}
catch {
    Write-Error ('uindos OneDrive policy: ' + $_.Exception.Message)
    exit 1
}
