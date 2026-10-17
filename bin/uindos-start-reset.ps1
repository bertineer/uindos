#Requires -Version 7.0
<#
.SYNOPSIS
    Preview a one-time empty Start layout; apply only with explicit layout-loss acknowledgment.
.DESCRIPTION
    Apply and UndoPolicy require temporary elevation as the Explorer desktop user.
    StateDirectory is a NEW private operation directory with an existing parent.
    Keep it on persistent storage. UndoPolicy restores only policy values, not pins.
    No sign-out, reboot, app removal, shell restart or cache edit is performed.
#>
[CmdletBinding(DefaultParameterSetName='Preview')]
param(
    [Parameter(Mandatory,ParameterSetName='Apply')][switch]$Apply,
    [Parameter(Mandatory,ParameterSetName='Apply')][switch]$AcknowledgeLayoutReset,
    [Parameter(Mandatory,ParameterSetName='UndoPolicy')][string]$UndoPolicy,
    [Parameter(Mandatory,ParameterSetName='Apply')]
    [Parameter(Mandatory,ParameterSetName='UndoPolicy')][string]$StateDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\StartResetWorkflow.ps1')
try {
    $options = @{Mode=$PSCmdlet.ParameterSetName}
    if ($PSCmdlet.ParameterSetName -ne 'Preview') { $options.StateDirectory=$StateDirectory }
    if ($PSCmdlet.ParameterSetName -eq 'Apply') { $options.AcknowledgeLayoutReset=$AcknowledgeLayoutReset }
    if ($PSCmdlet.ParameterSetName -eq 'UndoPolicy') { $options.TransactionId=$UndoPolicy }
    $response = Invoke-UindosStartReset @options
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -in @('blocked','needs-review')) { exit 2 }
} catch {
    Write-Error ('uindos Start reset: ' + $_.Exception.Message)
    exit 1
}
