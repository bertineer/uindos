#Requires -Version 7.0
# Read-only OneDrive Win32 preflight.
[CmdletBinding()]
param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\OneDrivePreflight.ps1')

try {
    $result = Get-UindosOneDrivePreflight
    $json = ConvertTo-Json -InputObject $result -Depth 8
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        Write-Output $json
    }
    else {
        $destination = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        $parent = Split-Path -Path $destination -Parent
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'Output directory does not exist.' }
        [System.IO.File]::WriteAllText($destination, "$json$([Environment]::NewLine)", [System.Text.UTF8Encoding]::new($false))
        Write-Output "OneDrive preflight saved locally to: $destination"
    }
}
catch {
    # Do not surface provider exception details that might contain private paths.
    Write-Error 'uindos OneDrive preflight failed; inspect locally with explicit troubleshooting.'
    exit 1
}
