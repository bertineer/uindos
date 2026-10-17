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

# Exercise the real Write delegate while intercepting the provider boundary.
# These local functions prevent every registry mutation in this test scope.
function Test-PrivacyWriteNormalization {
    $calls = [System.Collections.Generic.List[object]]::new()
    function Test-Path { param($LiteralPath, $ErrorAction) return $true }
    function New-Item { throw 'Unexpected registry key creation in test.' }
    function New-ItemProperty {
        param($LiteralPath, $Name, $PropertyType, $Value, [switch]$Force, $ErrorAction)
        $calls.Add([pscustomobject]@{ path=$LiteralPath; name=$Name; kind=$PropertyType; value=$Value })
    }
    $target = $actions[0]
    foreach ($priorValue in @([long]7, [long][int]::MinValue, [long][int]::MaxValue, [long]-1)) {
        & $adapter.Write $target.path $target.name 'DWord' $priorValue
        $call = $calls[$calls.Count - 1]
        Assert-Test ($call.path -ceq $target.path -and $call.name -ceq $target.name -and
            $call.kind -ceq 'DWord' -and $call.value -is [int] -and $call.value -eq $priorValue) 'Real Write normalizes journal DWORD before provider call'
    }
    $accepted = $calls.Count
    foreach ($invalid in @([long]2147483648, [long]-2147483649, '1', 1.5, $true, $null)) {
        $blocked = $false
        try { & $adapter.Write $target.path $target.name 'DWord' $invalid } catch { $blocked = $true }
        Assert-Test ($blocked -and $calls.Count -eq $accepted) 'Invalid journal integer rejected before provider call'
    }
}
Test-PrivacyWriteNormalization

# Avoid printing actual policy values, account details or Windows inventory.
Write-Output 'PASS: Windows privacy adapter read/allowlist and real Write integer checks (no production registry writes)'
