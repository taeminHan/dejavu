param(
    [Parameter(Mandatory = $true)][string]$ReleaseDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [Parameter(Mandatory = $true)][string]$Version
)

$ErrorActionPreference = 'Stop'
# This test installs a real product. Refuse a developer's normal Windows account:
# install/uninstall hooks and Start Menu changes belong only to disposable CI runners.
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_OS -ne 'Windows' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)) {
    throw 'Actual installation acceptance is restricted to an ephemeral GitHub Windows runner.'
}
$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseRoot = [System.IO.Path]::GetFullPath($ReleaseDirectory)
$evidenceRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$runnerRoot = [System.IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
if (-not $evidenceRoot.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installation evidence must be written below RUNNER_TEMP.'
}
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$installationRoot = Join-Path $env:RUNNER_TEMP ('dejavu-installed-' + [Guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $installationRoot) { throw 'The installation target must be new.' }
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Programs')) 'dejavu.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    throw 'A Dejavu Start Menu shortcut already exists. Refusing to overwrite another installation.'
}

$setupPath = Join-Path $releaseRoot 'dejavu-Setup.exe'
$installer = Start-Process -FilePath $setupPath -ArgumentList @('--silent', '--installto', ('"' + $installationRoot + '"')) -PassThru
if (-not $installer.WaitForExit(120000)) {
    $installer.Kill($true)
    throw 'The isolated setup exceeded its two-minute timeout.'
}
if ($installer.ExitCode -ne 0) { throw "The isolated setup failed with exit code $($installer.ExitCode)." }
if (-not (Test-Path -LiteralPath $shortcutPath)) { throw 'The real installer did not create its Start Menu shortcut.' }

$shell = New-Object -ComObject WScript.Shell
try {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $target = [System.IO.Path]::GetFullPath($shortcut.TargetPath)
    # Velopack 1.2.0's shortcuts.rs uses locator.get_main_exe_path(), which is
    # current/dejavu.exe. `current` is stable across updates; it is not app-0.x.y.
    # The separate root execution stub is also verified below, but is not the
    # Start Menu target produced by this pinned installer implementation.
    $expectedTarget = Join-Path $installationRoot 'current\dejavu.exe'
    if (-not $target.Equals($expectedTarget, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Start Menu must target the pinned Velopack current app, not an old version-specific file or Update.exe.'
    }
    if (-not [string]::IsNullOrWhiteSpace($shortcut.Arguments)) {
        throw 'The current Velopack shortcut unexpectedly contains launcher arguments.'
    }
    $iconLocation = [string]$shortcut.IconLocation
    $iconPath = $target
    $iconIndex = 0
    if (-not [string]::IsNullOrWhiteSpace($iconLocation)) {
        if ($iconLocation -notmatch '^(?<path>.*),(?<index>-?\d+)$') { throw 'The Start Menu icon location is invalid.' }
        $iconPath = [Environment]::ExpandEnvironmentVariables($Matches.path.Trim('"'))
        $iconIndex = [int]$Matches.index
        if ([string]::IsNullOrWhiteSpace($iconPath)) { $iconPath = $target }
    }
    $iconPath = [System.IO.Path]::GetFullPath($iconPath)
    $approvedIconPaths = @(
        (Join-Path $installationRoot 'dejavu.exe'),
        (Join-Path $installationRoot 'Update.exe'),
        (Join-Path $installationRoot 'current\dejavu.exe')
    )
    if ($iconIndex -ne 0 -or -not ($approvedIconPaths | Where-Object { $_.Equals($iconPath, [StringComparison]::OrdinalIgnoreCase) })) {
        throw 'The Start Menu shortcut does not resolve to a verified installed product icon.'
    }
    $shortcutReport = [ordered]@{
        schemaVersion = 1
        success = $true
        version = $Version
        installDirectory = $installationRoot
        shortcut = $shortcutPath
        target = $target
        arguments = [string]$shortcut.Arguments
        iconLocation = $iconLocation
        resolvedIconPath = $iconPath
        iconIndex = $iconIndex
        workingDirectory = [string]$shortcut.WorkingDirectory
        launcher = 'Velopack 1.2.0 stable current/dejavu.exe path'
        automaticApplicationStart = $false
    }
    $shortcutReport | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'installed-shortcut.json') -Encoding utf8NoBOM
} finally {
    if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
}

$installedApp = Join-Path $installationRoot 'current\dejavu.exe'
$installedVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($installedApp).ProductVersion
if ($installedVersion -notmatch ('^' + [regex]::Escape($Version) + '(\+|$)')) {
    throw 'The installed application version does not match the requested release.'
}
dotnet run --project (Join-Path $projectRoot 'tools\WindowsReleaseProbe\WindowsReleaseProbe.csproj') -c Release -- `
    --source-root $projectRoot --release-dir $releaseRoot --installed-root $installationRoot --version $Version --output $evidenceRoot
if ($LASTEXITCODE -ne 0) { throw 'Installed and packaged PE icon acceptance failed.' }

# Exercise the real installed executable through its controller-free safe branch.
# Never launch the normal UI, providers, login, persisted settings or update scheduler.
$runtimeEvidence = Join-Path $evidenceRoot 'installed-native-brand'
$runtime = Start-Process -FilePath $installedApp -ArgumentList ('--validate-brand="' + $runtimeEvidence + '"') -PassThru
if (-not $runtime.WaitForExit(60000)) {
    $runtime.Kill($true)
    throw 'Provider-free installed brand validation exceeded its one-minute timeout.'
}
if ($runtime.ExitCode -ne 0) { throw "Installed brand validation exited with $($runtime.ExitCode)." }
if (-not (Test-Path -LiteralPath $runtimeEvidence)) { throw 'Installed executable did not produce brand evidence.' }
$runtimeReports = @(Get-ChildItem -LiteralPath $runtimeEvidence -Filter '*.json' -File)
$runtimePreviews = @(Get-ChildItem -LiteralPath $runtimeEvidence -Filter '*.png' -File)
if ($runtimeReports.Count -lt 1 -or $runtimePreviews.Count -lt 3) {
    throw 'Installed brand acceptance must produce a structured report and native app/tray PNG evidence.'
}
$brandReport = Get-Content -LiteralPath (Join-Path $runtimeEvidence 'brand-validation.json') -Raw | ConvertFrom-Json
if ($brandReport.schemaVersion -ne 1 -or $brandReport.success -ne $true -or
    $brandReport.version -ne $Version -or $brandReport.failures.Count -ne 0 -or
    $brandReport.windowCases -ne 48 -or $brandReport.trayCases -ne 11 -or
    $brandReport.paletteCases -ne 13 -or $brandReport.notificationAreaAssignment -ne $true -or
    -not ([string]$brandReport.executable).Equals($installedApp, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'The installed native brand report is incomplete, failed, or was produced by a different executable.'
}
foreach ($name in $brandReport.exports) {
    if ([System.IO.Path]::GetFileName([string]$name) -ne [string]$name -or
        -not (Test-Path -LiteralPath (Join-Path $runtimeEvidence $name))) {
        throw 'The installed native brand report references missing or out-of-scope evidence.'
    }
}

$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\dejavu-desktop'
$installedRegistration = Get-ItemProperty -LiteralPath $uninstallKey
$displayIconPath = ([string]$installedRegistration.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"')
if ($installedRegistration.DisplayVersion -ne $Version -or
    -not ($approvedIconPaths | Where-Object { $_.Equals($displayIconPath, [StringComparison]::OrdinalIgnoreCase) })) {
    throw 'Windows Apps & Features does not reference the verified installed version/icon.'
}
[ordered]@{
    success = $true; version = $installedRegistration.DisplayVersion
    displayName = $installedRegistration.DisplayName; displayIcon = $installedRegistration.DisplayIcon
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot 'installed-apps-and-features.json') -Encoding utf8NoBOM

# Ask the Windows shell to resolve the actual .lnk icon rather than copying the source ICO.
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DejavuShortcutShellIcon {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct FileInfo {
        public IntPtr Icon;
        public int Index;
        public uint Attributes;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string DisplayName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 80)] public string TypeName;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern IntPtr SHGetFileInfo(string path, uint attributes, ref FileInfo info, uint size, uint flags);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr icon);
}
'@
$shellInfo = New-Object DejavuShortcutShellIcon+FileInfo
$result = [DejavuShortcutShellIcon]::SHGetFileInfo($shortcutPath, 0, [ref]$shellInfo,
    [Runtime.InteropServices.Marshal]::SizeOf($shellInfo), 0x100)
if ($result -eq [IntPtr]::Zero -or $shellInfo.Icon -eq [IntPtr]::Zero) { throw 'The shell could not resolve the installed shortcut icon.' }
try {
    $resolvedIcon = [Drawing.Icon]::FromHandle($shellInfo.Icon)
    $resolvedBitmap = $resolvedIcon.ToBitmap()
    try {
        $resolvedBitmap.Save((Join-Path $evidenceRoot 'installed-start-menu-shell-icon.png'), [Drawing.Imaging.ImageFormat]::Png)
        $referencePath = Join-Path $evidenceRoot ("approved-app-$($resolvedBitmap.Width).png")
        if (-not (Test-Path -LiteralPath $referencePath)) { throw 'The shell selected an unsupported app icon size.' }
        $reference = [Drawing.Bitmap]::new($referencePath)
        try {
            if ($reference.Width -ne $resolvedBitmap.Width -or $reference.Height -ne $resolvedBitmap.Height) { throw 'The shell icon size differs from the approved frame.' }
            $different = 0
            for ($y = 0; $y -lt $reference.Height; $y++) {
                for ($x = 0; $x -lt $reference.Width; $x++) {
                    $a = $reference.GetPixel($x, $y)
                    $b = $resolvedBitmap.GetPixel($x, $y)
                    # Premultiplied alpha round-tripping can change edge channels by one.
                    if ([Math]::Abs([int]$a.A - [int]$b.A) -gt 2 -or
                        [Math]::Abs(($a.R * $a.A / 255.0) - ($b.R * $b.A / 255.0)) -gt 2 -or
                        [Math]::Abs(($a.G * $a.A / 255.0) - ($b.G * $b.A / 255.0)) -gt 2 -or
                        [Math]::Abs(($a.B * $a.A / 255.0) - ($b.B * $b.A / 255.0)) -gt 2) { $different++ }
                }
            }
            if ($different -gt 0) { throw "The actual Start Menu shell icon has $different pixels that do not match the approved frame." }
        } finally { $reference.Dispose() }
    } finally { $resolvedBitmap.Dispose() }
} finally { [void][DejavuShortcutShellIcon]::DestroyIcon($shellInfo.Icon) }

Write-Host 'Windows installed release acceptance: real silent installation, pinned Velopack Start Menu target, resolved shell icon, all PE frames and provider-free native brand validation passed.'
Write-Host "Evidence: $evidenceRoot"
# Leave this isolated installation to the ephemeral runner's disposal. Do not run the
# real uninstall callback or remove broad product/user directories from a developer PC.
