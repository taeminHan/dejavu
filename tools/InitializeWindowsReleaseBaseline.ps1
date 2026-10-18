param(
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)][string]$CacheDirectory
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'The pinned logo-regression baseline is prepared only on disposable Windows CI runners.'
}
$runnerRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
foreach ($path in @($ReleaseDirectory, $CacheDirectory)) {
    if (-not [IO.Path]::GetFullPath($path).StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Baseline preparation must stay below RUNNER_TEMP.' }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
}
$name = 'dejavu-desktop-0.9.6-full.nupkg'
gh release download v0.9.6 --repo taeminHan/dejavu --pattern $name --pattern 'SHA256SUMS.txt' --dir $CacheDirectory
if ($LASTEXITCODE -ne 0) { throw 'The explicit public 0.9.6 baseline could not be downloaded.' }
$lines = @(Get-Content -LiteralPath (Join-Path $CacheDirectory 'SHA256SUMS.txt') | Where-Object { $_ -match ('^([0-9a-fA-F]{64})\s+' + [regex]::Escape($name) + '$') })
$source = Join-Path $CacheDirectory $name
if ($lines.Count -ne 1 -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne ($lines[0] -split '\s+')[0].ToLowerInvariant()) {
    throw 'The explicit 0.9.6 full package does not match its published checksum.'
}
$target = Join-Path $ReleaseDirectory $name
if (Test-Path -LiteralPath $target) { throw 'The release directory already contains a baseline; refusing to replace it.' }
Copy-Item -LiteralPath $source -Destination $target
Write-Host 'Prepared verified public v0.9.6 full package for deterministic 0.9.7 delta generation; latest release is not consulted.'
