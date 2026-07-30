param(
    [string]$Configuration = "Release",
    [string]$Version = "0.9.0-rc.1"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = (Resolve-Path (Join-Path $projectRoot "..\.." )).Path
$outputRoot = Join-Path $workspaceRoot "outputs"
$publishDirectory = Join-Path $outputRoot "dejavu-$Version"
$portableRoot = Join-Path $outputRoot "dejavu-$Version-portable"
$archivePath = Join-Path $outputRoot "dejavu-$Version-win-x64.zip"
$checksumsPath = Join-Path $outputRoot "SHA256SUMS.txt"
$projectFile = Join-Path $projectRoot "ClaudeUsageTray.csproj"
$bundledDotnet = Join-Path $workspaceRoot "work\dotnet-sdk\dotnet.exe"

$projectXml = [xml](Get-Content -LiteralPath $projectFile -Raw)
$projectVersion = [string]$projectXml.Project.PropertyGroup.Version
if ($projectVersion -ne $Version) {
    throw "Requested version '$Version' does not match project version '$projectVersion'."
}

$dotnet = if (Test-Path -LiteralPath $bundledDotnet) {
    $bundledDotnet
} else {
    (Get-Command dotnet -ErrorAction Stop).Source
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
if (Test-Path -LiteralPath $publishDirectory) {
    Remove-Item -LiteralPath $publishDirectory -Recurse -Force
}
if (Test-Path -LiteralPath $portableRoot) {
    Remove-Item -LiteralPath $portableRoot -Recurse -Force
}
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

& $dotnet publish $projectFile -c $Configuration -o $publishDirectory
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

New-Item -ItemType Directory -Path $portableRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $publishDirectory "dejavu.exe") -Destination $portableRoot
foreach ($document in @("README.md", "PRIVACY.md", "SECURITY.md", "CHANGELOG.md")) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $document) -Destination $portableRoot
}
$portableFiles = Get-ChildItem -LiteralPath $portableRoot -File
Compress-Archive -LiteralPath $portableFiles.FullName -DestinationPath $archivePath -CompressionLevel Optimal

$installerCompiler = @(
    "C:\Program Files (x86)\Inno Setup 7\ISCC.exe",
    "C:\Program Files\Inno Setup 7\ISCC.exe",
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    "C:\Program Files\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if ($installerCompiler) {
    & $installerCompiler (Join-Path $projectRoot "installer\dejavu.iss")
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup compilation failed with exit code $LASTEXITCODE."
    }
} else {
    Write-Warning "Inno Setup Compiler was not found. The portable package was built without an installer."
}

$artifacts = Get-ChildItem -LiteralPath $outputRoot -File |
    Where-Object { $_.Name -like "dejavu-$Version-*.zip" -or $_.Name -like "dejavu-Setup-$Version.exe" } |
    Sort-Object Name

$checksumLines = foreach ($artifact in $artifacts) {
    $hash = (Get-FileHash -LiteralPath $artifact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $($artifact.Name)"
}
Set-Content -LiteralPath $checksumsPath -Value $checksumLines -Encoding utf8NoBOM

Write-Host "Release artifacts:"
$artifacts | Select-Object Name, Length, FullName | Format-Table -AutoSize
Write-Host "Checksums: $checksumsPath"
