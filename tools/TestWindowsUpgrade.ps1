param(
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [string]$BaselineVersion = '0.9.6'
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'Upgrade acceptance is restricted to an ephemeral GitHub Windows runner.'
}
if ($BaselineVersion -ne '0.9.6' -or $Version -eq $BaselineVersion) {
    throw 'This logo-migration regression must begin with the public 0.9.6 baseline and apply a newer candidate.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = [IO.Path]::GetFullPath($ReleaseDirectory)
$evidenceRoot = [IO.Path]::GetFullPath($OutputDirectory)
$runnerRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
if (-not $evidenceRoot.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Upgrade evidence must stay below RUNNER_TEMP.' }
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$candidateChecksums = Get-Content -LiteralPath (Join-Path $releaseRoot 'SHA256SUMS.txt')
foreach ($name in @("dejavu-desktop-$Version-full.nupkg", 'dejavu-desktop-win-Portable.zip',
    'dejavu-desktop-win-Setup.exe', 'dejavu-Setup.exe', 'RELEASES', 'releases.win.json')) {
    $entry = @($candidateChecksums | Where-Object { $_ -match ('^([0-9a-fA-F]{64})\s+' + [regex]::Escape($name) + '$') })
    if ($entry.Count -ne 1 -or
        (Get-FileHash -LiteralPath (Join-Path $releaseRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant() -ne ($entry[0] -split '\s+')[0].ToLowerInvariant()) {
        throw "The exact candidate artifact does not match its checksum: $name"
    }
}
$baselineRoot = Join-Path $env:RUNNER_TEMP ('dejavu-baseline-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $baselineRoot | Out-Null
gh release download "v$BaselineVersion" --repo taeminHan/dejavu --pattern 'dejavu-Setup.exe' --pattern 'SHA256SUMS.txt' --dir $baselineRoot
if ($LASTEXITCODE -ne 0) { throw 'The public 0.9.6 baseline setup and checksum manifest could not be downloaded.' }
$baselineSetup = Join-Path $baselineRoot 'dejavu-Setup.exe'
$checksumLines = @(Get-Content -LiteralPath (Join-Path $baselineRoot 'SHA256SUMS.txt') | Where-Object { $_ -match '^([0-9a-fA-F]{64})\s+dejavu-Setup\.exe$' })
if ($checksumLines.Count -ne 1 -or
    (Get-FileHash -LiteralPath $baselineSetup -Algorithm SHA256).Hash.ToLowerInvariant() -ne ($checksumLines[0] -split '\s+')[0].ToLowerInvariant()) {
    throw 'The public baseline installer does not match its published checksum.'
}
$legacyContent = gh api 'repos/taeminHan/dejavu/contents/assets/dejavu.ico?ref=v0.9.6' --jq '.content'
if ($LASTEXITCODE -ne 0) { throw 'The public baseline icon source could not be obtained.' }
$legacyIcon = Join-Path $baselineRoot 'dejavu-0.9.6.ico'
[IO.File]::WriteAllBytes($legacyIcon, [Convert]::FromBase64String(($legacyContent -join '')))
if ((Get-FileHash -LiteralPath $legacyIcon -Algorithm SHA256).Hash.ToLowerInvariant() -ne
    '924c99ca9a3de54dbc722a4f0506664e8e115e005433dc522eaaddce669a8415') { throw 'The public baseline icon is not the expected old logo.' }
$installationRoot = Join-Path $env:RUNNER_TEMP ('dejavu-upgrade-install-' + [Guid]::NewGuid().ToString('N'))
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'dejavu.lnk'
if (Test-Path -LiteralPath $shortcutPath) { throw 'Upgrade acceptance requires its own clean runner; a Dejavu shortcut already exists.' }
$installer = Start-Process -FilePath $baselineSetup -ArgumentList @('--silent', '--installto', ('"' + $installationRoot + '"')) -PassThru
if (-not $installer.WaitForExit(120000)) { $installer.Kill($true); throw 'Baseline installation timed out.' }
if ($installer.ExitCode -ne 0) { throw 'Baseline installation failed.' }
$installedApp = Join-Path $installationRoot 'current\dejavu.exe'
$beforeVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($installedApp).ProductVersion
if ($beforeVersion -notmatch ('^' + [regex]::Escape($BaselineVersion) + '(\+|$)') -or -not (Test-Path -LiteralPath $shortcutPath)) {
    throw 'The actual baseline installation is missing its expected version or shortcut.'
}
dotnet run --project (Join-Path $projectRoot 'tools\WindowsReleaseProbe\WindowsReleaseProbe.csproj') -c Release -- `
    --source-root $projectRoot --legacy-installed-root $installationRoot --legacy-icon $legacyIcon --output (Join-Path $evidenceRoot 'baseline-precondition')
if ($LASTEXITCODE -ne 0) { throw 'The installed baseline does not contain every actual old-logo frame.' }
$before = foreach ($name in @('dejavu.exe', 'Update.exe', 'current\dejavu.exe')) {
    [ordered]@{ path = $name; sha256 = (Get-FileHash -LiteralPath (Join-Path $installationRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant() }
}
$beforeShortcutHash = (Get-FileHash -LiteralPath $shortcutPath -Algorithm SHA256).Hash.ToLowerInvariant()

$deltaReport = [ordered]@{ performed = $false; reason = 'Only the 0.9.7 logo migration has a pinned 0.9.6 delta baseline; this target uses the original full package.' }
$reconstructedPackage = $null
if ($Version -eq '0.9.7') {
    $deltaName = "dejavu-desktop-$Version-delta.nupkg"
    $deltaPath = Join-Path $releaseRoot $deltaName
    $deltaChecksums = @($candidateChecksums | Where-Object { $_ -match ('^([0-9a-fA-F]{64})\s+' + [regex]::Escape($deltaName) + '$') })
    if ($deltaChecksums.Count -ne 1 -or -not (Test-Path -LiteralPath $deltaPath) -or
        (Get-FileHash -LiteralPath $deltaPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne ($deltaChecksums[0] -split '\s+')[0].ToLowerInvariant()) {
        throw 'The 0.9.7 candidate must contain a delta matching its published candidate checksum.'
    }
    $baselineFullName = "dejavu-desktop-$BaselineVersion-full.nupkg"
    $baselineFullChecksums = @(Get-Content -LiteralPath (Join-Path $baselineRoot 'SHA256SUMS.txt') | Where-Object { $_ -match ('^([0-9a-fA-F]{64})\s+' + [regex]::Escape($baselineFullName) + '$') })
    if ($baselineFullChecksums.Count -ne 1) { throw 'The public baseline has no unique full-package checksum.' }
    $baselineFull = Join-Path $installationRoot "packages\$baselineFullName"
    $baselineSource = 'actual installed packages cache'
    if (-not (Test-Path -LiteralPath $baselineFull)) {
        gh release download "v$BaselineVersion" --repo taeminHan/dejavu --pattern $baselineFullName --dir $baselineRoot
        if ($LASTEXITCODE -ne 0) { throw 'The public baseline full package could not be downloaded.' }
        $baselineFull = Join-Path $baselineRoot $baselineFullName
        $baselineSource = 'explicit public release fallback'
    }
    $baselineFullHash = (Get-FileHash -LiteralPath $baselineFull -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($baselineFullHash -ne ($baselineFullChecksums[0] -split '\s+')[0].ToLowerInvariant()) { throw 'The installed baseline cache differs from the public full package.' }
    $reconstructedPackage = Join-Path $evidenceRoot "reconstructed-$Version-full.nupkg"
    # Use the actual installed 1.2.0 updater, before preparing the new updater,
    # in the same order as the production SDK's delta-download/prepare sequence.
    $patcher = Start-Process -FilePath (Join-Path $installationRoot 'Update.exe') -ArgumentList @('--silent', 'patch', '--old', ('"' + $baselineFull + '"'),
        '--delta', ('"' + $deltaPath + '"'), '--output', ('"' + $reconstructedPackage + '"')) -PassThru
    if (-not $patcher.WaitForExit(120000)) { $patcher.Kill($true); throw 'The real baseline updater delta reconstruction timed out.' }
    if ($patcher.ExitCode -ne 0) { throw "The baseline updater delta reconstruction failed with $($patcher.ExitCode)." }
    dotnet run --project (Join-Path $projectRoot 'tools\WindowsReleaseProbe\WindowsReleaseProbe.csproj') -c Release -- `
        --source-root $projectRoot --release-dir $releaseRoot --version $Version --reconstructed-package $reconstructedPackage `
        --output (Join-Path $evidenceRoot 'delta-reconstruction')
    if ($LASTEXITCODE -ne 0) { throw 'The reconstructed package differs from the verified original or failed actual icon acceptance.' }
    $deltaReport = [ordered]@{
        performed = $true; method = 'Installed baseline Update.exe --silent patch --old --delta --output'
        baselinePackageSource = $baselineSource; baselineFullSha256 = $baselineFullHash
        deltaPackage = $deltaName; deltaSha256 = (Get-FileHash -LiteralPath $deltaPath -Algorithm SHA256).Hash.ToLowerInvariant()
        originalFullSha256 = (Get-FileHash -LiteralPath (Join-Path $releaseRoot "dejavu-desktop-$Version-full.nupkg") -Algorithm SHA256).Hash.ToLowerInvariant()
        reconstructedFullSha256 = (Get-FileHash -LiteralPath $reconstructedPackage -Algorithm SHA256).Hash.ToLowerInvariant()
        contentComparison = 'Every ZIP entry path/type/uncompressed length/SHA256 matches; unsafe, symlink and duplicate entries rejected; reconstructed PE icons verified independently.'
    }
}

# Verify the exact candidate before allowing its updater to execute.
dotnet run --project (Join-Path $projectRoot 'tools\WindowsReleaseProbe\WindowsReleaseProbe.csproj') -c Release -- `
    --source-root $projectRoot --release-dir $releaseRoot --version $Version --output (Join-Path $evidenceRoot 'candidate-before-apply')
if ($LASTEXITCODE -ne 0) { throw 'The upgrade candidate did not pass artifact acceptance.' }
$packageName = "dejavu-desktop-$Version-full.nupkg"
$packagesRoot = Join-Path $installationRoot 'packages'
New-Item -ItemType Directory -Path $packagesRoot -Force | Out-Null
$stagedPackage = Join-Path $packagesRoot $packageName
Copy-Item -LiteralPath (Join-Path $releaseRoot $packageName) -Destination $stagedPackage
if ((Get-FileHash -LiteralPath $stagedPackage -Algorithm SHA256).Hash -ne
    (Get-FileHash -LiteralPath (Join-Path $releaseRoot $packageName) -Algorithm SHA256).Hash) { throw 'The staged package differs from the verified candidate.' }
if ($null -ne $reconstructedPackage) {
    # Actually apply the reconstructed bytes, not a silent fallback to original full.
    Copy-Item -LiteralPath $reconstructedPackage -Destination $stagedPackage -Force
    if ((Get-FileHash -LiteralPath $stagedPackage -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $reconstructedPackage -Algorithm SHA256).Hash) { throw 'The staged package differs from the verified delta reconstruction.' }
}

# The production SDK's DownloadUpdatesAsync finally block extracts Squirrel.exe
# to root Update.exe before applying. Reproduce that public, credential-free
# preparation exactly; do not launch the old app/controller or copy new app files.
$archive = [IO.Compression.ZipFile]::OpenRead($stagedPackage)
try {
    $entry = $archive.GetEntry('lib/app/Squirrel.exe')
    if ($null -eq $entry) { throw 'The verified candidate is missing its updater.' }
    $inputStream = $entry.Open()
    try {
        $outputStream = [IO.File]::Create((Join-Path $installationRoot 'Update.exe'))
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
    } finally { $inputStream.Dispose() }
} finally { $archive.Dispose() }

$updateExe = Join-Path $installationRoot 'Update.exe'
$updater = Start-Process -FilePath $updateExe -ArgumentList @('--silent', 'apply', '--norestart', '--package', ('"' + $stagedPackage + '"')) -PassThru
if (-not $updater.WaitForExit(120000)) { $updater.Kill($true); throw 'The real updater package-apply operation timed out.' }
if ($updater.ExitCode -ne 0) { throw "The real updater package apply failed with exit code $($updater.ExitCode)." }

& (Join-Path $PSScriptRoot 'TestWindowsRelease.ps1') -ReleaseDirectory $releaseRoot -OutputDirectory (Join-Path $evidenceRoot 'upgraded-installation') `
    -Version $Version -ExistingInstallation $installationRoot
$after = foreach ($name in @('dejavu.exe', 'Update.exe', 'current\dejavu.exe')) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $installationRoot $name) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -eq ($before | Where-Object { $_.path -eq $name }).sha256) { throw "The updater left a baseline executable unchanged: $name" }
    [ordered]@{ path = $name; sha256 = $hash }
}
[ordered]@{
    schemaVersion = 1; success = $true; baselineVersion = $BaselineVersion; targetVersion = $Version
    baselineInstallerSha256 = (Get-FileHash -LiteralPath $baselineSetup -Algorithm SHA256).Hash.ToLowerInvariant()
    appliedPackage = $packageName; appliedPackageSha256 = (Get-FileHash -LiteralPath $stagedPackage -Algorithm SHA256).Hash.ToLowerInvariant()
    method = 'Real Velopack 1.2.0 Update.exe --silent apply --norestart; SDK-equivalent updater preparation'
    deltaReconstruction = $deltaReport
    before = @($before); after = @($after); beforeShortcutSha256 = $beforeShortcutHash
    afterShortcutSha256 = (Get-FileHash -LiteralPath $shortcutPath -Algorithm SHA256).Hash.ToLowerInvariant()
    scope = 'Real existing-installation package apply and icon/shortcut/native-resource acceptance; no account/provider access or normal app start. Not automatic-update GUI or physical-DPI acceptance.'
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'windows-upgrade-acceptance.json') -Encoding utf8NoBOM
Write-Host "Windows upgrade logo acceptance: public $BaselineVersion -> $Version, real updater apply, 3 replaced executables, existing Start Menu shell pixels and native brand report passed."
