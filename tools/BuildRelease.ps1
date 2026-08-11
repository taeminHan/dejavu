param(
    [string]$Configuration = "Release",
    [string]$Version = "",
    [string]$OutputRoot = "",
    [switch]$DownloadPrevious
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = (Resolve-Path (Join-Path $projectRoot "..\.." )).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $workspaceRoot "outputs"
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$publishDirectory = Join-Path $outputRoot "dejavu-velopack-publish"
$releaseDirectory = Join-Path $outputRoot "dejavu-velopack-releases"
$checksumsPath = Join-Path $releaseDirectory "SHA256SUMS.txt"
$releaseNotesPath = Join-Path $outputRoot "dejavu-release-notes.md"
$packId = "dejavu-desktop"
$projectFile = Join-Path $projectRoot "ClaudeUsageTray.csproj"
$bundledDotnet = Join-Path $workspaceRoot "work\dotnet-sdk\dotnet.exe"
$bundledVpk = Join-Path $workspaceRoot "work\vpk-tool\vpk.exe"

$projectXml = [xml](Get-Content -LiteralPath $projectFile -Raw)
$projectVersion = [string]$projectXml.Project.PropertyGroup.Version
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $projectVersion
}
if ($projectVersion -ne $Version) {
    throw "Requested version '$Version' does not match project version '$projectVersion'."
}

$changelog = Get-Content -LiteralPath (Join-Path $projectRoot "CHANGELOG.md") -Raw
$escapedVersion = [regex]::Escape($Version)
$releaseNotesMatch = [regex]::Match($changelog,
    "(?ms)^##\s+$escapedVersion(?:\s+—[^\r\n]*)?\r?\n(?<notes>.*?)(?=^##\s+|\z)")
if (-not $releaseNotesMatch.Success) {
    throw "CHANGELOG.md does not contain a section for version '$Version'."
}
$releaseNotes = "# dejavu $Version`n`n" + $releaseNotesMatch.Groups["notes"].Value.Trim() + "`n"
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
Set-Content -LiteralPath $releaseNotesPath -Value $releaseNotes -Encoding utf8NoBOM

$dotnet = if (Test-Path -LiteralPath $bundledDotnet) {
    $bundledDotnet
} else {
    (Get-Command dotnet -ErrorAction Stop).Source
}
$vpk = if (Test-Path -LiteralPath $bundledVpk) {
    $env:DOTNET_ROOT = Split-Path -Parent $bundledDotnet
    $bundledVpk
} else {
    (Get-Command vpk -ErrorAction Stop).Source
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null
if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}

if ($DownloadPrevious) {
    $preRelease = $Version.Contains('-').ToString().ToLowerInvariant()
    & $vpk download github --repoUrl "https://github.com/taeminHan/dejavu" `
        --outputDir $releaseDirectory --channel win --pre $preRelease
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "No previous Velopack release was downloaded. A full package will be created."
    }
}

& $dotnet publish $projectFile -c $Configuration -r win-x64 --self-contained true -o $publishDirectory
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

& $vpk pack --packId $packId --packVersion $Version --packDir $publishDirectory `
    --mainExe dejavu.exe --packTitle dejavu --packAuthors taeminHan `
    --icon (Join-Path $projectRoot "assets\dejavu.ico") `
    --releaseNotes $releaseNotesPath `
    --runtime win-x64 --channel win --shortcuts StartMenuRoot `
    --outputDir $releaseDirectory
if ($LASTEXITCODE -ne 0) {
    throw "vpk pack failed with exit code $LASTEXITCODE."
}

$velopackSetup = Join-Path $releaseDirectory "$packId-win-Setup.exe"
$stableDownload = Join-Path $releaseDirectory "dejavu-Setup.exe"
if (-not (Test-Path -LiteralPath $velopackSetup)) {
    throw "Velopack setup was not created at '$velopackSetup'."
}
Copy-Item -LiteralPath $velopackSetup -Destination $stableDownload -Force

$currentArtifactNames = @(
    "$packId-$Version-full.nupkg",
    "$packId-$Version-delta.nupkg",
    "$packId-win-Portable.zip",
    "$packId-win-Setup.exe",
    "dejavu-Setup.exe",
    "RELEASES",
    "releases.win.json"
)
$requiredArtifactNames = @(
    "$packId-$Version-full.nupkg",
    "$packId-win-Portable.zip",
    "$packId-win-Setup.exe",
    "dejavu-Setup.exe",
    "RELEASES",
    "releases.win.json"
)
$missingArtifacts = $requiredArtifactNames | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $releaseDirectory $_))
}
if ($missingArtifacts) {
    throw "Velopack did not create required artifacts: $($missingArtifacts -join ', ')"
}
$artifacts = Get-ChildItem -LiteralPath $releaseDirectory -File |
    Where-Object { $_.Name -in $currentArtifactNames } |
    Sort-Object Name
$checksumLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($artifact.Name)"
}
Set-Content -LiteralPath $checksumsPath -Value $checksumLines -Encoding utf8NoBOM

Write-Host "Velopack release artifacts:"
$artifacts | Select-Object Name, Length, FullName | Format-Table -AutoSize
Write-Host "Checksums: $checksumsPath"
