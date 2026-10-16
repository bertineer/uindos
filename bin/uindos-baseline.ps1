# Requires -Version 7.0
<#
.SYNOPSIS
    Inspect Windows without changing operating-system state.
.EXAMPLE
    pwsh -NoProfile -File .\bin\uindos-baseline.ps1
.EXAMPLE
    pwsh -NoProfile -File .\bin\uindos-baseline.ps1 -OutputPath .\baseline.json
#>
[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Baseline.ps1')

try {
    $result = Get-UindosBaseline
    $json = ConvertTo-Json -InputObject $result -Depth 12
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        $parent = Split-Path -Path $destination -Parent
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            throw 'Output directory does not exist.'
        }
        [System.IO.File]::WriteAllText(
            $destination,
            "$json$([Environment]::NewLine)",
            [System.Text.UTF8Encoding]::new($false)
        )
        Write-Output "Baseline saved locally to: $destination"
    }
    else {
        Write-Output $json
    }
}
catch {
    Write-Error ("uindos baseline failed: " + $_.Exception.Message)
    exit 1
}
