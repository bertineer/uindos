# Portable context and CLI orchestration tests. Uses no Windows registry calls.
[CmdletBinding()]
param([string]$TestRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\Privacy.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

$validContext = [pscustomobject]@{
    elevated = $true
    sessionId = [long]3
    currentSid = 'S-1-5-21-100-200-300-1001'
    explorerProcesses = @([pscustomobject]@{
        sessionId = [long]3
        returnValue = [long]0
        sid = 'S-1-5-21-100-200-300-1001'
    })
}
Assert-UindosPrivacyContextObservations -Context $validContext

$invalidContexts = @(
    @{ context = [pscustomobject]@{ elevated=$false; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=$validContext.explorerProcesses }; reason='normal token' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=@([pscustomobject]@{sessionId=3;returnValue=0;sid='S-1-5-21-other'}) }; reason='different SID' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=@([pscustomobject]@{sessionId=4;returnValue=0;sid=$validContext.currentSid}) }; reason='different session' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=@() }; reason='missing Explorer' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=@([pscustomobject]@{sessionId=3;returnValue=5;sid=$null}) }; reason='failed owner probe' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=@([pscustomobject]@{sessionId=3;returnValue=$null;sid=$validContext.currentSid}) }; reason='unknown owner probe status' },
    @{ context = [pscustomobject]@{ elevated='true'; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=$validContext.explorerProcesses }; reason='unknown elevation state' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=$null; currentSid=$validContext.currentSid; explorerProcesses=$validContext.explorerProcesses }; reason='unknown session' },
    @{ context = [pscustomobject]@{ elevated=$true; sessionId=3; currentSid=$validContext.currentSid; explorerProcesses=@(
        $validContext.explorerProcesses[0], [pscustomobject]@{sessionId=3;returnValue=2;sid=$null}
    ) }; reason='one failed owner probe among Explorer processes' }
)
foreach ($case in $invalidContexts) {
    $rejected = $false
    try { Assert-UindosPrivacyContextObservations -Context $case.context } catch { $rejected = $true }
    Assert-Test $rejected "Context rejected: $($case.reason)"
}

# Exercise the real CLI with tiny in-memory engine/context doubles. The engine
# creates a journal directory only when reached, so ordering and no-effects
# guarantees are observable without a registry provider or Windows host.
$rootName = 'uindos-privacy-context-' + [Guid]::NewGuid().ToString('N')
$testBase = if ([string]::IsNullOrWhiteSpace($TestRoot)) { [IO.Path]::GetFullPath([IO.Path]::GetTempPath()) } else {
    if (-not [IO.Path]::IsPathFullyQualified($TestRoot)) { throw 'TestRoot must be an absolute existing directory.' }
    [IO.Path]::GetFullPath($TestRoot)
}
if (-not (Test-Path -LiteralPath $testBase -PathType Container)) { throw 'TestRoot must be an absolute existing directory.' }
$testBase = $testBase.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$tempRoot = Join-Path $testBase $rootName
$resolvedTempRoot = [IO.Path]::GetFullPath($tempRoot)
$binDir = Join-Path $tempRoot 'bin'
$coreDir = Join-Path $tempRoot 'src\core'
$foundationDir = Join-Path $tempRoot 'src\foundation'
$null = New-Item -ItemType Directory -Path $binDir,$coreDir,$foundationDir -Force
$cli = Join-Path $binDir 'uindos-privacy.ps1'
$eventsPath = Join-Path $tempRoot 'events.txt'
$journalPath = Join-Path $tempRoot 'journal-override'
$repoCli = Join-Path $PSScriptRoot '..\bin\uindos-privacy.ps1'
Copy-Item -LiteralPath $repoCli -Destination $cli

@'
function Get-UindosPlan { param($Actions,$Adapter) Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'plan'; [pscustomobject]@{ mode='read-only'; actions=@(); changeCount=0 } }
function Invoke-UindosApply { param($Actions,$Adapter,$JournalDirectory,[switch]$ConfirmChanges) Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'engine-apply'; $null=New-Item -ItemType Directory -Path $JournalDirectory -Force; Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'policy-write'; [pscustomobject]@{status='applied';transactionId='00000000-0000-0000-0000-000000000001'} }
function Invoke-UindosUndo { param($TransactionId,$Adapter,$JournalDirectory) Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'engine-undo'; $null=New-Item -ItemType Directory -Path $JournalDirectory -Force; Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'policy-write'; [pscustomobject]@{status='undone';transactionId=$TransactionId;conflicts=0} }
'@ | Set-Content -LiteralPath (Join-Path $coreDir 'Transactions.ps1')
@'
function Assert-UindosPrivacyContext { Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'context'; if ($env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL -eq '1') { throw 'mock context rejection' } }
function New-UindosPrivacyAdapter { Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'adapter'; @{} }
function Get-UindosPrivacyActions { Add-Content -LiteralPath $env:UINDOS_PRIVACY_TEST_LOG 'actions'; @([pscustomobject]@{id='privacy.test';path='HKCU:\Test';name='Value';kind='DWord';value=1}) }
'@ | Set-Content -LiteralPath (Join-Path $foundationDir 'Privacy.ps1')

$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$oldLog = $env:UINDOS_PRIVACY_TEST_LOG
$oldFail = $env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL
$oldLocal = $env:LOCALAPPDATA
try {
    $env:UINDOS_PRIVACY_TEST_LOG = $eventsPath
    Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue

    Remove-Item Env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL -ErrorAction SilentlyContinue
    $previewOutput = & $pwsh -NoProfile -File $cli 2>&1
    Assert-Test ($LASTEXITCODE -eq 0) 'Normal-user preview succeeds without LOCALAPPDATA'
    $previewEvents = @(Get-Content -LiteralPath $eventsPath)
    Assert-Test (($previewEvents -join ',') -eq 'adapter,actions,plan') 'Preview does not probe elevation or invoke write engine'
    Assert-Test (-not (Test-Path -LiteralPath $journalPath)) 'Preview creates no journal directory'

    foreach ($mode in @('apply','undo')) {
        Remove-Item -LiteralPath $eventsPath -ErrorAction SilentlyContinue
        $env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL = '1'
        if ($mode -eq 'apply') { $null = & $pwsh -NoProfile -File $cli -Apply -JournalDirectory $journalPath 2>&1 }
        else { $null = & $pwsh -NoProfile -File $cli -Undo '00000000-0000-0000-0000-000000000001' -JournalDirectory $journalPath 2>&1 }
        $rejectedEvents = @(Get-Content -LiteralPath $eventsPath)
        Assert-Test ($LASTEXITCODE -eq 1 -and ($rejectedEvents -join ',') -eq 'context') "$mode context rejection precedes adapter, journal, and policy effects (exit=$LASTEXITCODE; events=$($rejectedEvents -join ','))"
        Assert-Test (-not (Test-Path -LiteralPath $journalPath)) "$mode context rejection creates no journal directory"
    }

    Remove-Item Env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $eventsPath -ErrorAction SilentlyContinue
    $null = & $pwsh -NoProfile -File $cli -Apply -JournalDirectory $journalPath 2>&1
    $applyEvents = @(Get-Content -LiteralPath $eventsPath)
    Assert-Test ($LASTEXITCODE -eq 0 -and ($applyEvents -join ',') -eq 'context,adapter,actions,engine-apply,policy-write') 'Valid Apply reaches the mock engine with an absolute override and no LOCALAPPDATA'
    Assert-Test (Test-Path -LiteralPath $journalPath -PathType Container) 'Apply engine creates only the selected journal directory'

    [IO.Directory]::Delete($journalPath, $false)
    Remove-Item -LiteralPath $eventsPath -ErrorAction SilentlyContinue
    $null = & $pwsh -NoProfile -File $cli -Undo '00000000-0000-0000-0000-000000000001' -JournalDirectory $journalPath 2>&1
    $undoEvents = @(Get-Content -LiteralPath $eventsPath)
    Assert-Test ($LASTEXITCODE -eq 0 -and ($undoEvents -join ',') -eq 'context,adapter,engine-undo,policy-write') 'Valid Undo reaches the mock engine with an absolute override and no LOCALAPPDATA'

    [IO.Directory]::Delete($journalPath, $false)
    $fakeLocalAppData = Join-Path $resolvedTempRoot 'fake-local-appdata'
    $env:LOCALAPPDATA = $fakeLocalAppData
    Remove-Item -LiteralPath $eventsPath -ErrorAction SilentlyContinue
    $null = & $pwsh -NoProfile -File $cli -Apply 2>&1
    $defaultEvents = @(Get-Content -LiteralPath $eventsPath)
    $defaultJournalPath = Join-Path $fakeLocalAppData 'uindos\transactions\privacy-v1'
    Assert-Test ($LASTEXITCODE -eq 0 -and ($defaultEvents -join ',') -eq 'context,adapter,actions,engine-apply,policy-write') 'Apply retains the default LocalAppData journal behavior'
    Assert-Test (Test-Path -LiteralPath $defaultJournalPath -PathType Container) 'Default LocalAppData journal path is unchanged'

    [IO.Directory]::Delete($defaultJournalPath, $false)
    Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $eventsPath -ErrorAction SilentlyContinue
    $null = & $pwsh -NoProfile -File $cli -Apply -JournalDirectory 'relative-journal' 2>&1
    $invalidEvents = if (Test-Path -LiteralPath $eventsPath) { @(Get-Content -LiteralPath $eventsPath) } else { @() }
    Assert-Test ($LASTEXITCODE -eq 1 -and $invalidEvents.Count -eq 0) 'Relative override rejected before context or engine effects'
    Assert-Test (-not (Test-Path -LiteralPath (Join-Path $resolvedTempRoot 'relative-journal'))) 'Relative override creates no directory'

    $fileOverride = Join-Path $resolvedTempRoot 'not-a-directory'
    Set-Content -LiteralPath $fileOverride -Value 'test'
    Remove-Item -LiteralPath $eventsPath -ErrorAction SilentlyContinue
    $null = & $pwsh -NoProfile -File $cli -Undo '00000000-0000-0000-0000-000000000001' -JournalDirectory $fileOverride 2>&1
    $invalidEvents = if (Test-Path -LiteralPath $eventsPath) { @(Get-Content -LiteralPath $eventsPath) } else { @() }
    Assert-Test ($LASTEXITCODE -eq 1 -and $invalidEvents.Count -eq 0) 'File-valued override rejected before context or engine effects'

    Write-Output 'PASS: privacy context observations and CLI preview/apply/undo journal ordering'
}
finally {
    if ($null -eq $oldLog) { Remove-Item Env:UINDOS_PRIVACY_TEST_LOG -ErrorAction SilentlyContinue } else { $env:UINDOS_PRIVACY_TEST_LOG = $oldLog }
    if ($null -eq $oldFail) { Remove-Item Env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL -ErrorAction SilentlyContinue } else { $env:UINDOS_PRIVACY_TEST_CONTEXT_FAIL = $oldFail }
    if ($null -eq $oldLocal) { Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue } else { $env:LOCALAPPDATA = $oldLocal }
    if ($resolvedTempRoot.StartsWith($testBase, [StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedTempRoot) -match '^uindos-privacy-context-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedTempRoot)) {
        Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The final negative CLI case intentionally sets LASTEXITCODE to 1. GitHub's
# pwsh -command wrapper propagates it unless the successful suite exits itself.
exit 0
