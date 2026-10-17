# Portable PowerShell 7 tests for the pure Start pin report parser.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\foundation\StartPinsPreflight.ps1')
function Assert-Test { param([bool]$Condition,[string]$Message) if (-not $Condition) { throw "FAIL: $Message" } }
function Assert-Throws { param([scriptblock]$Action,[string]$Message) $failed=$false; try { & $Action | Out-Null } catch { $failed=$true }; Assert-Test $failed $Message }

$whatsApp = '5319275A.WhatsAppDesktop_cv1g1gvanyjgm!App'
$linkedin = '7EE7776C.LinkedInforWindows_w1wdnht996qgy!App'
$layout = [pscustomobject]@{ pinnedList=@(
    [pscustomobject]@{ packagedAppId=$whatsApp }
    [pscustomobject]@{ packagedAppId=$whatsApp }
    [pscustomobject]@{ desktopAppLink='private-path\secret.lnk' }
    [pscustomobject]@{ desktopAppId='Some.Other!App' }
    [pscustomobject]@{ packagedAppId=$linkedin }
) }
$report = ConvertTo-UindosStartPinsReport -Layout $layout -PackageFamilies @('5319275a.whatsappdesktop_cv1g1gvanyjgm','Other_family')
Assert-Test ($report.schema -eq 'uindos.start-pins-preflight/v1' -and $report.startPinCount -eq 5) 'Schema and exported pin count'
Assert-Test ($report.countsByType.packagedAppId -eq 3 -and $report.countsByType.desktopAppLink -eq 1 -and $report.countsByType.desktopAppId -eq 1) 'Pin type counts include duplicates'
Assert-Test ($report.targets[0].pinned -and $report.targets[0].currentUserPackageRegistered) 'Exact WhatsApp pin and family registration'
Assert-Test ($report.targets[1].pinned -and -not $report.targets[1].currentUserPackageRegistered) 'Exact LinkedIn pin with absent family registration'
Assert-Test ($report.assessment -eq 'manual-review-required') 'Manual review required'
$json = ConvertTo-Json -InputObject $report -Depth 8 -Compress
Assert-Test (-not $json.Contains('private-path') -and -not $json.Contains('Other_family') -and -not $json.Contains('Some.Other')) 'Arbitrary pin identities and family inventory are omitted'
Assert-Test ($json.Contains('not an exact undo') -and $json.Contains('does not establish whether its application is installed')) 'Limitations are explicit'
$caseVariantLayout = [pscustomobject]@{ pinnedList=@([pscustomobject]@{ packagedAppId='5319275a.whatsappdesktop_cv1g1gvanyjgm!app' }) }
$caseVariant = ConvertTo-UindosStartPinsReport -Layout $caseVariantLayout -PackageFamilies @('5319275A.WhatsAppDesktop_cv1g1gvanyjgm')
Assert-Test ($caseVariant.targets[0].pinned -and $caseVariant.targets[0].currentUserPackageRegistered) 'Canonical exact identity matching ignores case only'
$substring = ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@() }) -PackageFamilies @('prefix.5319275A.WhatsAppDesktop_cv1g1gvanyjgm.suffix')
Assert-Test (-not $substring.targets[0].currentUserPackageRegistered) 'Package family substring is not treated as identity match'

$empty = ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@() }) -PackageFamilies @()
Assert-Test ($empty.startPinCount -eq 0 -and @($empty.targets | Where-Object pinned).Count -eq 0) 'Empty pin list is valid'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{}) -PackageFamilies @() } 'Missing pinnedList rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList='bad' }) -PackageFamilies @() } 'Non-array pinnedList rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@([pscustomobject]@{ other='x' }) }) -PackageFamilies @() } 'Unknown pin identifier rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@([pscustomobject]@{ packagedAppId='x'; unsupportedId='y' }) }) -PackageFamilies @() } 'Mixed unknown pin identifier rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@([pscustomobject]@{ packagedAppId='x'; desktopAppId='y' }) }) -PackageFamilies @() } 'Ambiguous pin identifier rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@([pscustomobject]@{ packagedAppId=7 }) }) -PackageFamilies @() } 'Non-string pin identifier rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@() }) -PackageFamilies @('x',7) } 'Malformed package-family inventory rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@() }) -PackageFamilies @('') } 'Empty package-family value rejected'
Assert-Throws { ConvertTo-UindosStartPinsReport -Layout ([pscustomobject]@{ pinnedList=@() }) -PackageFamilies @('   ') } 'Whitespace package-family value rejected'
Write-Output 'PASS: Start pin preflight schema, exact identities, counts, privacy, empty and malformed exports'
