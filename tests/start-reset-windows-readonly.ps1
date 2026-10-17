# Windows-hosted adapter checks. Registry provider writes are intercepted;
# this suite never invokes Apply/Undo or changes native registry state.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows required.' }
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\StartReset.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }

$catalog = @(Get-UindosStartResetCatalog)
Assert-Test ($catalog.Count -eq 2 -and $catalog[0].kind -ceq 'ExpandString' -and $catalog[1].kind -ceq 'DWord') 'Fixed adapter catalog available on Windows'
$adapter = New-UindosStartResetAdapter
$plan = Get-UindosPlan -Actions $catalog -Adapter $adapter
Assert-Test ($plan.mode -eq 'read-only' -and $plan.actions.Count -eq 2) 'Native adapter reads both current values without mutation'

function Test-StartResetWriteNormalization {
    $calls = [System.Collections.Generic.List[object]]::new()
    function Test-Path { param($LiteralPath,$ErrorAction) return $true }
    function New-Item { throw 'Unexpected key creation in intercepted test.' }
    function New-ItemProperty {
        param($LiteralPath,$Name,$PropertyType,$Value,[switch]$Force,$ErrorAction)
        $calls.Add([pscustomobject]@{path=$LiteralPath;name=$Name;kind=$PropertyType;value=$Value})
    }
    $json = $catalog[0]
    $flag = $catalog[1]
    $raw = '%START_RESET_RAW%\\雪"quoted"'
    & $adapter.Write $json.path $json.name 'ExpandString' $raw
    $call = $calls[$calls.Count-1]
    Assert-Test ($call.path -ceq $json.path -and $call.name -ceq $json.name -and $call.kind -ceq 'ExpandString' -and
        $call.value -is [string] -and $call.value -ceq $raw) 'ExpandString writer passes literal raw string through unchanged'
    foreach ($prior in @([long]0,[long]7,[long]-1,[long][int]::MinValue,[long][int]::MaxValue)) {
        & $adapter.Write $flag.path $flag.name 'DWord' $prior
        $call = $calls[$calls.Count-1]
        Assert-Test ($call.path -ceq $flag.path -and $call.name -ceq $flag.name -and $call.kind -ceq 'DWord' -and
            $call.value -is [int] -and $call.value -eq $prior) 'Writer normalizes journal Int64 to signed DWORD'
    }
    $accepted = $calls.Count
    foreach ($case in @(
        @{path=$json.path;name=$json.name;kind='ExpandString';value=1},
        @{path=$flag.path;name=$flag.name;kind='DWord';value=[long]2147483648},
        @{path=$flag.path;name=$flag.name;kind='DWord';value='1'},
        @{path=$json.path;name=$json.name;kind='String';value=$raw},
        @{path='HKLM:\SOFTWARE\Microsoft\Windows';name=$flag.name;kind='DWord';value=1},
        @{path=$flag.path;name='LockedStartLayout';kind='DWord';value=1}
    )) {
        $blocked = $false
        try { & $adapter.Write $case.path $case.name $case.kind $case.value } catch { $blocked = $true }
        Assert-Test ($blocked -and $calls.Count -eq $accepted) 'Wrong type, coercion or target rejected before provider write'
    }
}
Test-StartResetWriteNormalization

try { & $adapter.Read 'HKLM:\SOFTWARE\Microsoft\Windows' $catalog[0].name; throw 'Wrong read target unexpectedly accepted.' }
catch { if ($_.Exception.Message -eq 'Wrong read target unexpectedly accepted.') { throw } }
try { & $adapter.Remove $catalog[0].path 'LockedStartLayout'; throw 'Wrong remove target unexpectedly accepted.' }
catch { if ($_.Exception.Message -eq 'Wrong remove target unexpectedly accepted.') { throw } }

Write-Output 'PASS: Windows Start reset adapter allowlist, raw ExpandString read plan, and intercepted Write normalization (no registry mutations)'
