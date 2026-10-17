# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo the curated dark theme and black desktop background.
.DESCRIPTION
    Defaults to a read-only plan. Apply/Undo require the non-elevated Explorer
    user's interactive session. No image downloads, wallpaper deletion, service
    changes, Explorer restarts, or sign-out. Uses exact private state journals.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo,
    [string]$JournalDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Appearance.ps1')
try {
    $actions = @(Get-UindosAppearanceActions)
    $adapter = New-UindosAppearanceAdapter
    if (-not $PSBoundParameters.ContainsKey('JournalDirectory')) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA is unavailable; provide a private JournalDirectory.' }
        $JournalDirectory = Join-Path $env:LOCALAPPDATA 'uindos\transactions\appearance-v1'
    }
    if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        $response = Get-UindosPlan -Actions $actions -Adapter $adapter
    } else {
        Assert-UindosAppearanceContext
        $response = $null
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Undo') {
                $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $JournalDirectory
            } else {
                $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $JournalDirectory -ConfirmChanges
            }
        } finally {
            # Some steps may have been restored even after a failed transaction.
            $refresh = if ($null -ne $response -and $response.status -eq 'unchanged') {
                [pscustomobject]@{notified=$false;reason='unchanged';timedOut=$false}
            } else { Invoke-UindosThemeRefresh }
        }
        $response | Add-Member -NotePropertyName themeRefresh -NotePropertyValue $refresh
    }
    $response | Add-Member -NotePropertyName visualNote -NotePropertyValue 'Verify desktop and app UI separately. Wallpaper source/slide position and lock screen are not managed by this command.'
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
} catch {
    Write-Error ('uindos appearance: ' + $_.Exception.Message)
    exit 1
}
