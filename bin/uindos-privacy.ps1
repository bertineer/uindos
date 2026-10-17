# Requires -Version 7.0
<#
.SYNOPSIS
    Preview or explicitly apply uindos privacy v1 for the current Windows 11 Pro user.
.DESCRIPTION
    Default is a read-only plan. -Apply persists a local journal before writing.
    -Undo <transaction-guid> restores the exact prior values where safe.
.EXAMPLE
    pwsh -NoProfile -File ./bin/uindos-privacy.ps1
.EXAMPLE
    pwsh -NoProfile -File ./bin/uindos-privacy.ps1 -Apply
.EXAMPLE
    pwsh -NoProfile -File ./bin/uindos-privacy.ps1 -Undo <transaction-guid>
#>
[CmdletBinding(DefaultParameterSetName='Plan')]
param(
    [Parameter(ParameterSetName='Apply',Mandatory)][switch]$Apply,
    [Parameter(ParameterSetName='Undo',Mandatory)][string]$Undo,
    [Parameter()][string]$JournalDirectory
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Privacy.ps1')

try {
    $journalOverride = $null
    if ($PSBoundParameters.ContainsKey('JournalDirectory')) {
        if ([string]::IsNullOrWhiteSpace($JournalDirectory) -or
            -not [IO.Path]::IsPathFullyQualified($JournalDirectory)) {
            throw 'JournalDirectory must be a valid absolute path.'
        }
        try { $journalOverride = [IO.Path]::GetFullPath($JournalDirectory) }
        catch { throw 'JournalDirectory must be a valid absolute path.' }
        if ((Test-Path -LiteralPath $journalOverride) -and
            -not (Test-Path -LiteralPath $journalOverride -PathType Container)) {
            throw 'JournalDirectory exists but is not a directory.'
        }
    }

    # Preview remains usable as the ordinary desktop user and never needs a
    # journal location. Apply/Undo require temporary elevation in Explorer's
    # same SID/session before the engine can create or read a journal.
    if ($PSCmdlet.ParameterSetName -eq 'Undo') {
        Assert-UindosPrivacyContext
        $adapter = New-UindosPrivacyAdapter
        if ($null -ne $journalOverride) { $journal = $journalOverride }
        else {
            if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
                throw 'LOCALAPPDATA is unavailable. Refusing to store transaction journal.'
            }
            $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\privacy-v1'
        }
        $response = Invoke-UindosUndo -TransactionId $Undo -Adapter $adapter -JournalDirectory $journal
    }
    else {
        if ($PSCmdlet.ParameterSetName -eq 'Apply') { Assert-UindosPrivacyContext }
        $adapter = New-UindosPrivacyAdapter
        # Explicitly fail rather than attempting unsupported Windows editions.
        $actions = @(Get-UindosPrivacyActions)
        if ($PSCmdlet.ParameterSetName -eq 'Apply') {
            if ($null -ne $journalOverride) { $journal = $journalOverride }
            else {
                if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
                    throw 'LOCALAPPDATA is unavailable. Refusing to store transaction journal.'
                }
                $journal = Join-Path $env:LOCALAPPDATA 'uindos\transactions\privacy-v1'
            }
            $response = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $journal -ConfirmChanges
        }
        else {
            $response = Get-UindosPlan -Actions $actions -Adapter $adapter
        }
    }
    ConvertTo-Json -InputObject $response -Depth 15
    if ($PSCmdlet.ParameterSetName -eq 'Undo' -and $response.status -eq 'needs-review') {
        exit 2
    }
}
catch {
    Write-Error ("uindos privacy: " + $_.Exception.Message)
    exit 1
}
