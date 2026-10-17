# Requires -Version 7.0
<#
.SYNOPSIS
    Preview, apply, or undo the current-user search-box suggestions policy.
.DESCRIPTION
    The documented policy suppresses File Explorer search history suggestions.
    Start web-result behavior must be observed separately on each Windows build.
    Default preview is read-only. Apply/Undo use a temporary elevated policy
    command for the same user/session as the normal Explorer desktop.
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo,
    [string]$JournalDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\SearchSuggestions.ps1')
try {
    $actions = @(Get-UindosSearchSuggestionsActions)
    $adapter = New-UindosSearchSuggestionsAdapter
    if (-not $PSBoundParameters.ContainsKey('JournalDirectory')) {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA unavailable; provide a private JournalDirectory.' }
        $JournalDirectory = Join-Path $env:LOCALAPPDATA 'uindos\transactions\search-suggestions-v1'
    }
    if ($PSCmdlet.ParameterSetName -eq 'Plan') {
        $response = Get-UindosPlan -Actions $actions -Adapter $adapter
    } else {
        Assert-UindosSearchSuggestionsContext
        if ($PSCmdlet.ParameterSetName -eq 'Undo') {
            $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $JournalDirectory
        } else {
            $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $JournalDirectory -ConfirmChanges
        }
    }
    $response | Add-Member -NotePropertyName behaviorNote -NotePropertyValue 'Registry readback is not proof of Start web-result suppression. Check local Search and UI separately; a later sign-in may be needed.'
    ConvertTo-Json -InputObject $response -Depth 15
    if ($response.status -eq 'needs-review') { exit 2 }
} catch {
    Write-Error ('uindos search suggestions: ' + $_.Exception.Message)
    exit 1
}
