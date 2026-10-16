# Windows-hosted read-only privacy guard checks. No supported policy values are modified.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows required.' }
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Privacy.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$adapter = New-UindosPrivacyAdapter
$actions = @(Get-UindosPrivacyRuleCatalog)
$plan = Get-UindosPlan -Actions $actions -Adapter $adapter
Assert-Test ($plan.actions.Count -eq 3) 'Read-only real Windows privacy plan'
Assert-Test ($plan.mode -eq 'read-only') 'Plan mode'

$blocked = $false
try { & $adapter.Write 'HKLM:\SOFTWARE\Microsoft\Windows' 'Unrelated' 'DWord' 1 }
catch { $blocked = $true }
Assert-Test $blocked 'Real adapter blocks arbitrary machine registry writes'

$blocked = $false
try { & $adapter.Write $actions[0].path $actions[0].name 'String' 'bad' }
catch { $blocked = $true }
Assert-Test $blocked 'Real adapter blocks incorrect registry type'

$blocked = $false
try { & $adapter.Remove 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' }
catch { $blocked = $true }
Assert-Test $blocked 'Real adapter blocks unrelated values even within parent key'

# Avoid printing actual policy values, account details or Windows inventory.
Write-Output 'PASS: Windows privacy adapter read/allowlist checks (no production registry writes)'
