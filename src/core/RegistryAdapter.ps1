# M3 preview: intentionally restricted to HKCU:\Software\uindos\EngineTest.
# Do not widen this allowlist until individual production policies are reviewed.

function Assert-UindosSandboxRegistryPath {
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -notmatch '^HKCU:\\Software\\uindos\\EngineTest(?:\\|$)') {
        throw [System.NotSupportedException]::new('M3 registry writes are limited to HKCU:\Software\uindos\EngineTest.')
    }
}

function New-UindosRegistryAdapter {
    # The adapter is a set of fixed operations. No manifest-supplied PowerShell.
    return @{
        Read = {
            param([string]$Path, [string]$Name)
            Assert-UindosSandboxRegistryPath -Path $Path
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
            }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -cnotcontains $Name) {
                return [pscustomobject]@{ exists = $false; kind = $null; value = $null }
            }
            $kind = $key.GetValueKind($Name).ToString()
            if ($kind -notin @('String', 'DWord', 'QWord')) {
                throw [System.NotSupportedException]::new('Registry value type is outside the M3 allowlist.')
            }
            return [pscustomobject]@{
                exists = $true
                kind = $kind
                value = $key.GetValue($Name, $null)
            }
        }
        Write = {
            param([string]$Path, [string]$Name, [string]$Kind, $Value)
            Assert-UindosSandboxRegistryPath -Path $Path
            if ($Kind -notin @('String', 'DWord', 'QWord')) {
                throw 'Unsupported registry kind.'
            }
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) {
                New-Item -Path $Path -Force -ErrorAction Stop | Out-Null
            }
            New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType $Kind -Value $Value -Force -ErrorAction Stop | Out-Null
        }
        Remove = {
            param([string]$Path, [string]$Name)
            Assert-UindosSandboxRegistryPath -Path $Path
            if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return }
            $key = Get-Item -LiteralPath $Path -ErrorAction Stop
            if (@($key.GetValueNames()) -ccontains $Name) {
                Remove-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
            }
        }
    }
}
