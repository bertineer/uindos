# Windows-only checks for the production adapter. Registry writes are intercepted.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Windows required.' }
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\EdgeBackground.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$adapter = New-UindosEdgeBackgroundAdapter
$actions = @(Get-UindosEdgeBackgroundPolicyCatalog)
Assert-Test ($actions.Count -eq 2) 'Exactly two allowlisted Edge policy targets'

# Exercise production Read on the exact allowlist without asserting prior state.
# A wrong-kind value is an acceptable fail-closed observation; no value is printed.
foreach ($action in $actions) {
    try {
        $state = & $adapter.Read $action.path $action.name
        Assert-Test ($state.exists -is [bool]) 'Production Read returns an explicit existence state'
        if ($state.exists) {
            Assert-Test ($state.kind -ceq 'DWord' -and ($state.value -is [int] -or $state.value -is [long])) 'Production Read returns typed DWORD data'
        }
    }
    catch [System.NotSupportedException] {
        # A pre-existing wrong registry kind must be rejected, without revealing it.
    }
}

$blocked = $false
try { & $adapter.Read 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DoNotAllowEdgeUpdate' }
catch [System.NotSupportedException] { $blocked = $true }
Assert-Test $blocked 'Production Read rejects an unrelated value in the allowed parent key'

# Intercept provider calls while invoking the real Write delegate. The local
# functions shadow registry-provider commands for the duration of this helper.
function Test-EdgeWriteNormalization {
    $calls = [System.Collections.Generic.List[object]]::new()
    function Test-Path { param($LiteralPath, $ErrorAction) return $true }
    function New-Item { throw 'Unexpected registry key creation in test.' }
    function New-ItemProperty {
        param($LiteralPath, $Name, $PropertyType, $Value, [switch]$Force, $ErrorAction)
        $calls.Add([pscustomobject]@{ path=$LiteralPath; name=$Name; kind=$PropertyType; value=$Value })
    }
    foreach ($target in $actions) {
        foreach ($priorValue in @([long]7, [long][int]::MinValue, [long][int]::MaxValue, [long]-1)) {
            & $adapter.Write $target.path $target.name 'DWord' $priorValue
            $call = $calls[$calls.Count - 1]
            Assert-Test ($call.path -ceq $target.path -and $call.name -ceq $target.name -and
                $call.kind -ceq 'DWord' -and $call.value -is [int] -and $call.value -eq $priorValue) 'Production Write normalizes prior DWORD before provider call'
        }
    }
    $accepted = $calls.Count
    foreach ($invalid in @([long]2147483648, [long]-2147483649, '1', 1.5, $true, $null)) {
        $blocked = $false
        try { & $adapter.Write $actions[0].path $actions[0].name 'DWord' $invalid } catch { $blocked = $true }
        Assert-Test ($blocked -and $calls.Count -eq $accepted) 'Production Write rejects malformed prior values before provider call'
    }
    $blocked = $false
    try { & $adapter.Write 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DoNotAllowEdgeUpdate' 'DWord' 0 }
    catch [System.NotSupportedException] { $blocked = $true }
    Assert-Test ($blocked -and $calls.Count -eq $accepted) 'Production Write blocks unrelated policy values before provider call'
}
Test-EdgeWriteNormalization

# Intercept Read's provider boundary and supply a fake wrong-kind registry key.
# This calls the production Read delegate but never opens or changes the live key.
function Test-EdgeWrongKindRead {
    $script:edgeFakeReadCalls = 0
    function Test-Path { param($LiteralPath, $ErrorAction) $script:edgeFakeReadCalls++; return $true }
    function Get-Item {
        param($LiteralPath, $ErrorAction)
        $fake = [pscustomobject]@{}
        Add-Member -InputObject $fake -MemberType ScriptMethod -Name GetValueNames -Value { return @('StartupBoostEnabled') }
        Add-Member -InputObject $fake -MemberType ScriptMethod -Name GetValueKind -Value { param($Name) return [Microsoft.Win32.RegistryValueKind]::String }
        Add-Member -InputObject $fake -MemberType ScriptMethod -Name GetValue -Value { param($Name,$Default) return '0' }
        return $fake
    }
    $blocked = $false
    try { [void](& $adapter.Read $actions[0].path $actions[0].name) }
    catch [System.NotSupportedException] { $blocked = $true }
    Assert-Test ($blocked -and $script:edgeFakeReadCalls -eq 1) 'Production Read rejects a fake existing non-DWORD without a second provider operation'
}
Test-EdgeWrongKindRead

# Keep the output free of live policy values, user identity, and machine inventory.
Write-Output 'PASS: Windows Edge adapter allowlist/read and intercepted Write/wrong-kind checks (no production registry writes)'
