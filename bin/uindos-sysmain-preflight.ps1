#Requires -Version 7.0
# Read-only fixed-target SysMain state preflight.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\SysMainPreflight.ps1')

try {
    $result = Get-UindosSysMainPreflight
    ConvertTo-Json -InputObject $result -Depth 8
}
catch {
    # Provider exceptions can include private system details; never print their text.
    Write-Error 'uindos SysMain preflight failed; no service changes were requested.'
    exit 1
}
