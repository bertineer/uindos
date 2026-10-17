[CmdletBinding()]
param([Parameter(Mandatory)][string]$ArtifactDirectory)
$ErrorActionPreference = 'Stop'
try {
    $artifactDirectory = [IO.Path]::GetFullPath($ArtifactDirectory)
    if (-not [IO.Directory]::Exists($artifactDirectory)) { throw 'Artifact directory must already exist.' }
    $layoutPath = Join-Path $artifactDirectory 'layout.json'
    $familiesPath = Join-Path $artifactDirectory 'families.json'
    if ([IO.File]::Exists($layoutPath) -or [IO.File]::Exists($familiesPath) -or
        [IO.Directory]::Exists($layoutPath) -or [IO.Directory]::Exists($familiesPath)) {
        throw 'Evidence files already exist; refusing to overwrite them.'
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Collector must run without elevation.' }

    $explorer = @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)
    $sameSession = @($explorer | Where-Object { $_.SessionId -eq (Get-Process -Id $PID).SessionId })
    if ($sameSession.Count -eq 0) { throw 'No Explorer process exists in this session.' }
    $owned = $false
    foreach ($process in $sameSession) {
        $owner = Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
        if ($owner.ReturnValue -eq 0 -and $owner.Sid -ceq $identity.User.Value) { $owned = $true; break }
    }
    if (-not $owned) { throw 'Collector identity does not own Explorer in this session.' }
    if (-not (Get-Command Export-StartLayout -ErrorAction SilentlyContinue)) { throw 'Export-StartLayout is unavailable.' }

    Export-StartLayout -Path $layoutPath -ErrorAction Stop
    $families = @(Get-AppxPackage -ErrorAction Stop | ForEach-Object { [string]$_.PackageFamilyName } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $payload = [pscustomobject]@{
        packageFamilies = [string[]]$families
        context = [pscustomobject]@{ elevated = $false; sameUserAsExplorer = $true }
    } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText($familiesPath,$payload,[System.Text.UTF8Encoding]::new($false))
    exit 0
} catch {
    # Do not write exception details to stdout/stderr; they may contain private paths or identities.
    exit 1
}
