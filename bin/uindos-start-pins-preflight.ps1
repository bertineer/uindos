# Requires -Version 7.0
<#
.SYNOPSIS
    Read-only current-user Start pin inventory with sanitized JSON output.
.DESCRIPTION
    Uses the inbox Windows PowerShell layout export. Temporary private export
    artifacts are cleaned up unless PrivateExportDirectory is explicitly set.
    No pin, app, policy, registry or shell-process state is changed.
#>
[CmdletBinding()]
param([string]$PrivateExportDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\StartPinsPreflight.ps1')
try {
    $parameters=@{}
    if($PSBoundParameters.ContainsKey('PrivateExportDirectory')){$parameters.PrivateExportDirectory=$PrivateExportDirectory}
    $report=Get-UindosStartPinsPreflight @parameters
    ConvertTo-Json -InputObject $report -Depth 12
}catch{
    Write-Error ('uindos Start pins preflight failed: '+$_.Exception.GetType().Name+'. No pin or policy changes were requested.')
    exit 1
}
