param(
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
$releaseRoot = [IO.Path]::GetFullPath($ReleaseDirectory)
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$feedPath = Join-Path $releaseRoot 'releases.win.json'
$legacyPath = Join-Path $releaseRoot 'RELEASES'
$feed = Get-Content -LiteralPath $feedPath -Raw | ConvertFrom-Json
$assets = @($feed.Assets)
if ($assets.Count -lt 1 -or $assets.Count -gt 2) { throw 'The update index must contain the current full package and at most one current delta.' }
$seenNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$seenTypes = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$checks = foreach ($asset in $assets) {
    $type = [string]$asset.Type
    $name = [string]$asset.FileName
    if ($asset.PackageId -cne 'dejavu-desktop' -or $asset.Version -cne $Version -or
        $type -cnotin @('Full', 'Delta') -or -not $seenNames.Add($name) -or -not $seenTypes.Add($type)) {
        throw 'The update index contains an unexpected package/version/type or duplicate entry.'
    }
    $suffix = $type.ToLowerInvariant()
    if ($name -cne "dejavu-desktop-$Version-$suffix.nupkg" -or [IO.Path]::GetFileName($name) -cne $name) {
        throw 'The update index package filename does not match its exact version/type.'
    }
    if ([string]$asset.SHA1 -notmatch '^[0-9a-fA-F]{40}$' -or [string]$asset.SHA256 -notmatch '^[0-9a-fA-F]{64}$' -or
        [string]$asset.Size -notmatch '^[1-9][0-9]*$') { throw 'The update index contains an invalid hash or size.' }
    $path = Join-Path $releaseRoot $name
    $file = Get-Item -LiteralPath $path
    $sha1 = (Get-FileHash -LiteralPath $path -Algorithm SHA1).Hash
    $sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($file.Length -ne [long]$asset.Size -or $sha1 -ine $asset.SHA1 -or $sha256 -ine $asset.SHA256) {
        throw "The update index does not match the actual uploaded package bytes: $name"
    }
    [ordered]@{ fileName = $name; type = $type; version = $Version; size = $file.Length; sha1 = $sha1.ToLowerInvariant(); sha256 = $sha256.ToLowerInvariant() }
}
if (-not $seenTypes.Contains('Full') -or ($Version -eq '0.9.7' -and -not $seenTypes.Contains('Delta'))) {
    throw 'The expected current full package or required 0.9.7 delta is missing from the update index.'
}

# Velopack's upload code deliberately serializes these feeds again. Compare the
# exact parsed records and package hashes, not BOM/newline/property-order bytes.
$legacy = @(Get-Content -LiteralPath $legacyPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($legacy.Count -ne 1 -or $legacy[0].Trim() -notmatch '^(?<sha1>[0-9a-fA-F]{40})[ \t]+(?<file>[^ \t]+)[ \t]+(?<size>[0-9]+)$') {
    throw 'The legacy feed must contain exactly one valid current full-package record.'
}
$legacyHash = $Matches.sha1
$legacyName = $Matches.file
$legacySize = $Matches.size
$full = @($checks | Where-Object { $_.type -eq 'Full' })[0]
if ($legacyName -cne $full.fileName -or $legacyHash -ine $full.sha1 -or
    $legacySize -notmatch '^[1-9][0-9]*$' -or [long]$legacySize -ne $full.size) {
    throw 'The legacy feed and JSON full record do not describe the same verified package.'
}
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
[ordered]@{
    schemaVersion = 1; success = $true; version = $Version; packageId = 'dejavu-desktop'
    jsonEntries = $assets.Count; legacyEntries = $legacy.Count; packages = @($checks)
    jsonFileSha256 = (Get-FileHash -LiteralPath $feedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    legacyFileSha256 = (Get-FileHash -LiteralPath $legacyPath -Algorithm SHA256).Hash.ToLowerInvariant()
    scope = 'Exact current package/version/type/name, uniqueness, actual downloaded package SHA1/SHA256 and size; one equivalent legacy full record. Only serialization BOM/newlines/property order are immaterial.'
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $outputRoot 'windows-update-feed-validation.json') -Encoding utf8NoBOM
Write-Host "Windows uploaded update feeds: $($assets.Count) JSON packages and 1 legacy full record, actual SHA1/SHA256/size matched, 0 failures."
