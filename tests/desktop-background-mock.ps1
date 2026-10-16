# Cross-platform mock tests for the fixed desktop background adapter.
# No registry or native desktop wallpaper settings are touched.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\core\Transactions.ps1')
. (Join-Path $PSScriptRoot '..\src\foundation\DesktopBackground.ps1')

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "FAIL: $Message" }
}

function New-MockDesktopBackgroundBackend {
    return @{
        Read = {
            if ($script:mockReadFailure) { throw 'Injected monitor query failure.' }
            return [pscustomobject]@{
                Color = $script:mockDesktop.Color
                ImageVisible = $script:mockDesktop.ImageVisible
                MonitorCount = $script:mockDesktop.MonitorCount
            }
        }
        SetColor = {
            param($Value)
            $script:mockDesktop.Color = [int]$Value
            $script:mockDesktop.ColorWrites++
        }
        SetImageVisible = {
            param($Value)
            $script:mockDesktop.ImageVisible = [int]$Value
            $script:mockDesktop.ImageVisibleWrites++
        }
    }
}

$actions = @(Get-UindosDesktopBackgroundActions)
Assert-Test ($actions.Count -eq 2) 'Exactly two synthetic API actions'
Assert-Test ((@($actions | Where-Object { $_.value -eq 0 -and $_.kind -ceq 'DWord' }).Count) -eq 2) 'Both curated actions target zero'
Assert-Test ((@($actions | Where-Object { $_.path -cne 'desktop:background' }).Count) -eq 0) 'Fixed synthetic target path'

$script:mockDesktop = [pscustomobject]@{
    Color = [long]0x345678
    ImageVisible = 1
    MonitorCount = 2
    ColorWrites = 0
    ImageVisibleWrites = 0
}
$script:mockReadFailure = $false
$backend = New-MockDesktopBackgroundBackend
$adapter = New-UindosDesktopBackgroundAdapter -Backend $backend
$dir = Join-Path ([IO.Path]::GetTempPath()) ('uindos-desktop-background-mock-' + [Guid]::NewGuid().ToString('N'))

try {
    $plan = Get-UindosPlan -Actions $actions -Adapter $adapter
    Assert-Test ($plan.changeCount -eq 2) 'Visible image and nonblack color are planned'
    Assert-Test ($script:mockDesktop.ColorWrites -eq 0 -and $script:mockDesktop.ImageVisibleWrites -eq 0) 'Preview has no writes'

    $applied = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $script:mockDesktop.Color -eq 0 -and
        $script:mockDesktop.ImageVisible -eq 0) 'Apply sets black and disables visible image'
    Assert-Test ($script:mockDesktop.ColorWrites -eq 1 -and $script:mockDesktop.ImageVisibleWrites -eq 1) 'Apply uses each native operation once'

    $again = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($again.status -eq 'unchanged' -and $script:mockDesktop.ColorWrites -eq 1 -and
        $script:mockDesktop.ImageVisibleWrites -eq 1) 'Repeated Apply is a no-op'

    $undo = Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:mockDesktop.Color -eq 0x345678 -and
        $script:mockDesktop.ImageVisible -eq 1) 'Undo restores exact color and re-enables previously visible image'
    Assert-Test ($script:mockDesktop.ColorWrites -eq 2 -and $script:mockDesktop.ImageVisibleWrites -eq 2) 'Undo performs only the required restores'

    # A desktop that already has no visible image has an ambiguous Enable state.
    # The synthetic image action remains unchanged, preserving that state.
    $script:mockDesktop.Color = [long]0xabcdef
    $script:mockDesktop.ImageVisible = 0
    $script:mockDesktop.ColorWrites = 0
    $script:mockDesktop.ImageVisibleWrites = 0
    $plan = Get-UindosPlan -Actions $actions -Adapter $adapter
    Assert-Test ($plan.changeCount -eq 1) 'Already-empty image state plans only color'
    $applied = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    Assert-Test ($applied.status -eq 'applied' -and $script:mockDesktop.ImageVisibleWrites -eq 0) 'Apply leaves unknown prior Enable state untouched'
    $undo = Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($undo.status -eq 'undone' -and $script:mockDesktop.Color -eq 0xabcdef -and
        $script:mockDesktop.ImageVisible -eq 0 -and $script:mockDesktop.ImageVisibleWrites -eq 0) 'Undo restores prior color without enabling an initially empty desktop'

    # A changed color is drift. Undo restores the image state, then refuses to
    # overwrite the externally changed color.
    $script:mockDesktop.Color = [long]0x123456
    $script:mockDesktop.ImageVisible = 1
    $script:mockDesktop.ColorWrites = 0
    $script:mockDesktop.ImageVisibleWrites = 0
    $applied = Invoke-UindosApply -Actions $actions -Adapter $adapter -JournalDirectory $dir -ConfirmChanges
    $script:mockDesktop.Color = 0x777777
    $conflict = Invoke-UindosUndo -TransactionId $applied.transactionId -Adapter $adapter -JournalDirectory $dir
    Assert-Test ($conflict.status -eq 'needs-review' -and $conflict.conflicts -eq 1) 'Undo reports changed desktop color'
    Assert-Test ($script:mockDesktop.Color -eq 0x777777 -and $script:mockDesktop.ImageVisible -eq 1) 'Drift is preserved while other state is restored'

    foreach ($mutant in @(
        [pscustomobject]@{ id='desktop.background-color'; path='HKCU:\Software\uindos'; name='Color'; kind='DWord'; value=0 },
        [pscustomobject]@{ id='desktop.background-image-visible'; path='desktop:background'; name='ImageVisible'; kind='String'; value='0' },
        [pscustomobject]@{ id='desktop.background-color'; path='desktop:background'; name='Color'; kind='DWord'; value=1 },
        [pscustomobject]@{ id='desktop.unlisted'; path='desktop:background'; name='Color'; kind='DWord'; value=0 }
    )) {
        $rejected = $false
        try { [void](Get-UindosPlan -Actions @($mutant) -Adapter $adapter) }
        catch { $rejected = $true }
        Assert-Test $rejected 'Modified action denied'
    }

    $blocked = $false
    try { & $adapter.Write 'desktop:background' 'Color' 'DWord' ([long]0x1000000) }
    catch { $blocked = $true }
    Assert-Test $blocked 'Out-of-range COLORREF rejected'
    $blocked = $false
    try { & $adapter.Write 'desktop:background' 'ImageVisible' 'DWord' ([long]2) }
    catch { $blocked = $true }
    Assert-Test $blocked 'ImageVisible values outside 0/1 rejected'
    $blocked = $false
    try { & $adapter.Remove 'desktop:background' 'Color' }
    catch [System.NotSupportedException] { $blocked = $true }
    Assert-Test $blocked 'Native API target removal rejected'

    $script:mockReadFailure = $true
    $blocked = $false
    try { [void](Get-UindosPlan -Actions $actions -Adapter $adapter) }
    catch { $blocked = $true }
    Assert-Test $blocked 'Per-monitor read failure refuses unknown state'
    $script:mockReadFailure = $false
    $script:mockDesktop.MonitorCount = 0
    $blocked = $false
    try { [void](Get-UindosPlan -Actions $actions -Adapter $adapter) }
    catch { $blocked = $true }
    Assert-Test $blocked 'No-monitor state refuses unknown image visibility'

    Write-Output 'PASS: desktop background adapter fixed targets, preview, apply, no-op, exact undo, drift, validation, and unknown-state refusal'
}
finally {
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $fullDirectory = [IO.Path]::GetFullPath($dir)
    $expectedPrefix = Join-Path $tempRoot 'uindos-desktop-background-mock-'
    if ($fullDirectory.StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $fullDirectory)) {
        Remove-Item -LiteralPath $fullDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
