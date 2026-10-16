# Combined theme and desktop-background transaction tests. All native behavior
# is replaced with injected in-memory adapters; no Windows state is accessed.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\Appearance.ps1')

function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }

$os=[pscustomobject]@{editionId='Professional';build='26300';architecture='X64'}
$actions=@(Get-UindosAppearanceActions -OsInfo $os)
Assert-Test ($actions.Count -eq 4) 'combined appearance plan has two theme and two background actions'
Assert-Test (@($actions | Where-Object id -like 'theme.*').Count -eq 2) 'two theme actions'
Assert-Test (@($actions | Where-Object id -like 'desktop.*').Count -eq 2) 'two desktop background actions'

$script:themeState=@{}
$script:themeWrites=0
$script:desktopState=[pscustomobject]@{Color=1193046;ImageVisible=1;MonitorCount=2}
$script:denyDesktopWrite=$false
$themeAdapter=@{
    ValidateAction={ param($Action) Assert-UindosThemeAction -Action $Action }
    Read={
        param($Path,$Name)
        $key="$Path|$Name"
        if ($script:themeState.ContainsKey($key)) { return $script:themeState[$key] }
        [pscustomobject]@{exists=$false;kind=$null;value=$null}
    }
    Write={
        param($Path,$Name,$Kind,$Value)
        $script:themeState["$Path|$Name"]=[pscustomobject]@{exists=$true;kind=$Kind;value=[int]$Value}
        $script:themeWrites++
    }
    Remove={ param($Path,$Name) [void]$script:themeState.Remove("$Path|$Name") }
}
$desktopBackend=@{
    Read={ return $script:desktopState }
    SetColor={
        param($Value)
        if ($script:denyDesktopWrite) { throw [UnauthorizedAccessException]::new('Mock denied desktop background write.') }
        $script:desktopState.Color=[int]$Value
    }
    SetImageVisible={
        param($Value)
        if ($script:denyDesktopWrite) { throw [UnauthorizedAccessException]::new('Mock denied desktop background write.') }
        $script:desktopState.ImageVisible=[int]$Value
    }
}
$desktopAdapter=New-UindosDesktopBackgroundAdapter -Backend $desktopBackend
$adapter=New-UindosAppearanceAdapter -ThemeAdapter $themeAdapter -DesktopAdapter $desktopAdapter

$initialTheme=@{}
foreach ($action in @($actions | Where-Object id -like 'theme.*')) {
    $key="$($action.path)|$($action.name)"
    $initialTheme[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=1}
    $script:themeState[$key]=[pscustomobject]@{exists=$true;kind='DWord';value=1}
}
$initialDesktop=[pscustomobject]@{Color=1193046;ImageVisible=1;MonitorCount=2}
$dir=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath())) ("uindos-appearance-"+[guid]::NewGuid().ToString('N'))
try {
    $plan=Get-UindosPlan -Actions $actions -Adapter $adapter
    Assert-Test ($plan.changeCount -eq 4 -and $script:themeWrites -eq 0 -and -not (Test-Path -LiteralPath $dir)) 'four-action preview performs no writes'

    $applied=Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $applied.changeCount -eq 4) 'combined appearance Apply succeeds'
    Assert-Test ($script:desktopState.Color -eq 0 -and $script:desktopState.ImageVisible -eq 0) 'background defaults applied'
    Assert-Test (@($script:themeState.Values | Where-Object value -ne 0).Count -eq 0) 'both theme defaults applied'
    $themeWritesAfterApply=$script:themeWrites
    $again=Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($again.status -eq 'unchanged' -and $script:themeWrites -eq $themeWritesAfterApply) 'combined Apply is idempotent'

    $journal=Get-Content -Raw -LiteralPath (Join-Path $dir "$($applied.transactionId).json") | ConvertFrom-Json -Depth 20
    Assert-Test ($journal.steps.Count -eq 4 -and @($journal.steps | Where-Object { $_.prior.exists }).Count -eq 4) 'journal captures all four exact prior states'
    $undone=Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($undone.status -eq 'undone') 'combined Undo succeeds'
    foreach ($key in $initialTheme.Keys) {
        Assert-Test ($script:themeState[$key].value -eq $initialTheme[$key].value) 'Undo restores exact prior theme DWORD'
    }
    Assert-Test ($script:desktopState.Color -eq $initialDesktop.Color -and $script:desktopState.ImageVisible -eq $initialDesktop.ImageVisible) 'Undo restores exact prior desktop API state'

    # Fail the first background write after both theme writes. Undo must use
    # the transaction JSON to restore both themes and leave the API state intact.
    $script:denyDesktopWrite=$true
    $themeWritesBeforeFailure=$script:themeWrites
    $applyFailed=$false
    try { [void](Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges) }
    catch { $applyFailed=$true }
    finally { $script:denyDesktopWrite=$false }
    Assert-Test $applyFailed 'background write denial fails the combined transaction'
    Assert-Test ($script:themeWrites -ge ($themeWritesBeforeFailure+4)) 'both theme steps were written and rolled back'
    foreach ($key in $initialTheme.Keys) {
        Assert-Test ($script:themeState[$key].value -eq $initialTheme[$key].value) 'failed background Apply restores prior theme DWORDs'
    }
    Assert-Test ($script:desktopState.Color -eq $initialDesktop.Color -and $script:desktopState.ImageVisible -eq $initialDesktop.ImageVisible) 'failed background Apply preserves API state'
    $failureJournal=@(Get-ChildItem -LiteralPath $dir -Filter '*.json' | ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json -Depth 20 } | Where-Object status -eq 'rolled-back')
    Assert-Test ($failureJournal.Count -eq 1 -and $failureJournal[0].steps.Count -eq 4) 'JSON journal records completed rollback'

    # Start from the same exact prior state, apply, then simulate drift on just
    # one theme value. Undo must keep that drift and restore the other 3 steps.
    $driftApply=Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    $driftAction=@($actions | Where-Object id -eq 'theme.dark-apps')[0]
    $driftKey="$($driftAction.path)|$($driftAction.name)"
    $script:themeState[$driftKey]=[pscustomobject]@{exists=$true;kind='DWord';value=2}
    $driftUndo=Invoke-UindosUndo -TransactionId $driftApply.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($driftUndo.status -eq 'needs-review' -and $driftUndo.conflicts -eq 1) 'one-sided drift reports needs-review'
    Assert-Test ($script:themeState[$driftKey].value -eq 2) 'Undo preserves the drifted value'
    Assert-Test ($script:themeState["$($actions[1].path)|$($actions[1].name)"].value -eq 1) 'Undo restores the other theme value'
    Assert-Test ($script:desktopState.Color -eq $initialDesktop.Color -and $script:desktopState.ImageVisible -eq $initialDesktop.ImageVisible) 'Undo restores both background values despite theme drift'

    # The router must reject swapped scopes before permissive injected adapters
    # are called. These spies intentionally accept every path and value.
    $script:permissiveCalls=0
    $permissive=@{
        Read={ param($Path,$Name) $script:permissiveCalls++; [pscustomobject]@{exists=$false;kind=$null;value=$null} }
        Write={ param($Path,$Name,$Kind,$Value) $script:permissiveCalls++ }
        Remove={ param($Path,$Name) $script:permissiveCalls++ }
    }
    $permissiveDesktop=New-UindosDesktopBackgroundAdapter -Backend @{
        Read={ return [pscustomobject]@{Color=0;ImageVisible=0;MonitorCount=1} }
        SetColor={ param($Value) $script:permissiveCalls++ }
        SetImageVisible={ param($Value) $script:permissiveCalls++ }
    }
    $guarded=New-UindosAppearanceAdapter -ThemeAdapter $permissive -DesktopAdapter $permissiveDesktop
    $blocked=$false
    try { [void](& $guarded.Read 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'Color') } catch [System.NotSupportedException] { $blocked=$true }
    Assert-Test $blocked 'theme adapter cannot read desktop-only field'
    $blocked=$false
    try { [void](& $guarded.Read 'desktop:background' 'AppsUseLightTheme') } catch [System.NotSupportedException] { $blocked=$true }
    Assert-Test ($blocked -and $script:permissiveCalls -eq 0) 'desktop adapter cannot read theme-only field'
    $blocked=$false
    try { & $guarded.Write 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'Color' 'DWord' 0 } catch [System.NotSupportedException] { $blocked=$true }
    Assert-Test ($blocked -and $script:permissiveCalls -eq 0) 'cross-target write rejected before permissive adapter'
    $blocked=$false
    try { [void](Get-UindosPlan -Actions @([pscustomobject]@{id='theme.dark-apps';path='desktop:background';name='AppsUseLightTheme';kind='DWord';value=0}) -Adapter $guarded) } catch [System.NotSupportedException] { $blocked=$true }
    Assert-Test ($blocked -and $script:permissiveCalls -eq 0) 'cross-target action rejected by router validation'

    Write-Output 'PASS: combined appearance preview/apply/undo, JSON rollback after background denial, drift conflict, target routing'
}
finally {
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resolvedRoot=$tempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    $resolvedDir=[IO.Path]::GetFullPath($dir)
    if ($resolvedDir.StartsWith($resolvedRoot,[StringComparison]::OrdinalIgnoreCase) -and
        [IO.Path]::GetFileName($resolvedDir) -match '^uindos-appearance-[0-9a-f]{32}$' -and
        (Test-Path -LiteralPath $resolvedDir)) {
        Remove-Item -LiteralPath $resolvedDir -Recurse -Force
    }
}
