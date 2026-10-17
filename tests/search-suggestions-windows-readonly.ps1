# Windows-hosted checks for the real adapter. Registry provider writes are
# intercepted locally; this test does not alter the Windows registry.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows required.' }
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\SearchSuggestions.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$adapter = New-UindosSearchSuggestionsAdapter
$actions = @(Get-UindosSearchSuggestionsCatalog)
$plan = Get-UindosPlan -Actions $actions -Adapter $adapter
Assert-Test ($plan.mode -eq 'read-only' -and $plan.actions.Count -eq 1) 'Real Windows adapter read-only plan'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $blockedContext = $false
    try { Assert-UindosSearchSuggestionsContext } catch { $blockedContext = $true }
    Assert-Test $blockedContext 'Non-elevated Apply/Undo context rejected'
}

function Test-SearchSuggestionsWriteNormalization {
    $calls = [System.Collections.Generic.List[object]]::new()
    function Test-Path { param($LiteralPath,$ErrorAction) return $true }
    function New-Item { throw 'Unexpected key creation in intercepted test.' }
    function New-ItemProperty {
        param($LiteralPath,$Name,$PropertyType,$Value,[switch]$Force,$ErrorAction)
        $calls.Add([pscustomobject]@{path=$LiteralPath;name=$Name;kind=$PropertyType;value=$Value})
    }
    $rule = $actions[0]
    foreach ($prior in @([long]0,[long]7,[long]-1,[long][int]::MinValue,[long][int]::MaxValue)) {
        & $adapter.Write $rule.path $rule.name 'DWord' $prior
        $call = $calls[$calls.Count-1]
        Assert-Test ($call.path -ceq $rule.path -and $call.name -ceq $rule.name -and
            $call.kind -ceq 'DWord' -and $call.value -is [int] -and $call.value -eq $prior) 'Real Write normalizes prior JSON integer to signed DWORD'
    }
    $accepted = $calls.Count
    foreach ($invalid in @([long]2147483648,[long]-2147483649,'1',1.5,[decimal]1,$true,$null)) {
        $blocked = $false
        try { & $adapter.Write $rule.path $rule.name 'DWord' $invalid } catch { $blocked = $true }
        Assert-Test ($blocked -and $calls.Count -eq $accepted) 'Invalid DWORD rejected before provider write'
    }
    foreach ($case in @(
        @{path='HKLM:\SOFTWARE\Microsoft\Windows';name=$rule.name;kind='DWord';value=1},
        @{path=$rule.path;name='OtherValue';kind='DWord';value=1},
        @{path=$rule.path;name=$rule.name;kind='String';value='1'},
        @{path=$rule.path;name=$rule.name;kind='QWord';value=1}
    )) {
        $blocked = $false
        try { & $adapter.Write $case.path $case.name $case.kind $case.value } catch { $blocked = $true }
        Assert-Test ($blocked -and $calls.Count -eq $accepted) 'Wrong target or kind rejected before provider write'
    }
}
Test-SearchSuggestionsWriteNormalization

try { & $adapter.Read 'HKLM:\SOFTWARE\Microsoft\Windows' $actions[0].name; throw 'Wrong read target unexpectedly accepted.' }
catch { if ($_.Exception.Message -eq 'Wrong read target unexpectedly accepted.') { throw } }
try { & $adapter.Remove $actions[0].path 'OtherValue'; throw 'Wrong remove target unexpectedly accepted.' }
catch { if ($_.Exception.Message -eq 'Wrong remove target unexpectedly accepted.') { throw } }

Write-Output 'PASS: Windows Search suggestions adapter allowlist and real Write normalization (provider writes intercepted; no registry mutations)'
