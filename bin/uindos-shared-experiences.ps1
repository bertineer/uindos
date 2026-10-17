# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo the supported Windows 11 Pro cross-device participation policy.
.DESCRIPTION
    This manages only the machine ADMX EnableCDP policy (EnableCdp DWORD 0).
    Apply requires clear authority probes and an already elevated shell. Undo
    uses the journal and exact-value conflict guard, without rechecking current
    management state.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo,
    [Parameter()][string]$JournalDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\SharedExperiences.ps1')

try {
    $adapter = New-UindosSharedExperiencesAdapter
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        Assert-UindosSharedExperiencesWriteAuthorization -IsAdministrator (Test-UindosSharedExperiencesAdministrator)
        $journal = Get-UindosSharedExperiencesJournalDirectory -JournalDirectory $JournalDirectory -HasOverride ($PSBoundParameters.ContainsKey('JournalDirectory')) -LocalAppData $env:LOCALAPPDATA
        # Undo deliberately does not gate on current management state; exact
        # journal validation and the engine drift guard protect recovery.
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    else {
        $authority = Get-UindosSharedExperiencesAuthority
        $actions = @(Get-UindosSharedExperiencesActions)
        if ($PSCmdlet.ParameterSetName -eq 'Plan') {
            $response = Get-UindosPlan -Actions $actions -Adapter $adapter
            $response | Add-Member -NotePropertyName authority -NotePropertyValue $authority
        }
        else {
            # Probe management authority before resolving/creating a journal.
            Assert-UindosSharedExperiencesAuthority -Authority $authority
            Assert-UindosSharedExperiencesWriteAuthorization -IsAdministrator (Test-UindosSharedExperiencesAdministrator)
            $journal = Get-UindosSharedExperiencesJournalDirectory -JournalDirectory $JournalDirectory -HasOverride ($PSBoundParameters.ContainsKey('JournalDirectory')) -LocalAppData $env:LOCALAPPDATA
            $response = Invoke-UindosSharedExperiencesApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -Authority $authority
            $response | Add-Member -NotePropertyName authority -NotePropertyValue $authority
        }
    }
    $response | Add-Member -NotePropertyName behaviorNote -NotePropertyValue 'EnableCdp=0 prevents this device from being discoverable and participating in cross-device continuation after reboot. It does not promise CDP services stop or reduce memory. Microsoft states Windows settings backup does not work when EnableCDP is disabled.'
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
}
catch {
    Write-Error ('uindos shared-experiences policy: ' + $_.Exception.Message)
    exit 1
}
