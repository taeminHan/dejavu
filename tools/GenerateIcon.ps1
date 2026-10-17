param(
    [string]$IconOutputPath = (Join-Path $PSScriptRoot '..\assets\dejavu.ico')
)

# Windows-only asset generation. Run with: pwsh -STA -File tools/GenerateIcon.ps1
# Geometry and colors are read from the approved production SVGs, never redrawn here.
$ErrorActionPreference = 'Stop'
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'The WPF SVG renderer requires STA. Run pwsh -STA -File tools/GenerateIcon.ps1.'
}
Add-Type -AssemblyName WindowsBase, PresentationCore
$projectRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($IconOutputPath))
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$iconSizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Get-SvgNumber([System.Xml.XmlElement]$Element, [string]$Name, [double]$Default = 0) {
    if (-not $Element.HasAttribute($Name)) { return $Default }
    return [double]::Parse($Element.GetAttribute($Name), $invariant)
}

function Get-SvgTransform([string]$Value) {
    $group = [System.Windows.Media.TransformGroup]::new()
    $operations = [regex]::Matches($Value, '(translate|scale)\(([^)]+)\)')
    if ($operations.Count -eq 0 -or ([regex]::Replace($Value, '(translate|scale)\(([^)]+)\)', '').Trim()).Length -gt 0) {
        throw "Unsupported SVG transform: $Value"
    }
    # SVG's list applies right-to-left; WPF's TransformGroup applies left-to-right.
    for ($index = $operations.Count - 1; $index -ge 0; $index--) {
        $operation = $operations[$index]
        $values = @($operation.Groups[2].Value.Trim() -split '[ ,]+' | ForEach-Object { [double]::Parse($_, $invariant) })
        if ($operation.Groups[1].Value -eq 'translate') {
            $y = if ($values.Count -gt 1) { $values[1] } else { 0 }
            $group.Children.Add([System.Windows.Media.TranslateTransform]::new($values[0], $y))
        } else {
            $y = if ($values.Count -gt 1) { $values[1] } else { $values[0] }
            $group.Children.Add([System.Windows.Media.ScaleTransform]::new($values[0], $y))
        }
    }
    return $group
}

function Draw-SvgElement([System.Xml.XmlElement]$Element, $Context, [string]$Ink) {
    $transformed = $Element.HasAttribute('transform')
    if ($transformed) { $Context.PushTransform((Get-SvgTransform $Element.GetAttribute('transform'))) }
    try {
        switch ($Element.LocalName) {
            'title' { return }
            'svg' { foreach ($child in $Element.ChildNodes) { if ($child -is [System.Xml.XmlElement]) { Draw-SvgElement $child $Context $Ink } } }
            'g' { foreach ($child in $Element.ChildNodes) { if ($child -is [System.Xml.XmlElement]) { Draw-SvgElement $child $Context $Ink } } }
            { $_ -in 'path', 'rect' } {
                $fill = $Element.GetAttribute('fill')
                if ($fill -eq 'currentColor') { $fill = $Ink }
                if ([string]::IsNullOrWhiteSpace($fill) -or $fill -eq 'none') { throw 'Brand paths must declare a solid fill.' }
                $brush = [System.Windows.Media.BrushConverter]::new().ConvertFromInvariantString($fill)
                if ($Element.LocalName -eq 'path') {
                    $Context.DrawGeometry($brush, $null, [System.Windows.Media.Geometry]::Parse($Element.GetAttribute('d')))
                } else {
                    $bounds = [System.Windows.Rect]::new((Get-SvgNumber $Element 'x'), (Get-SvgNumber $Element 'y'),
                        (Get-SvgNumber $Element 'width'), (Get-SvgNumber $Element 'height'))
                    $radius = Get-SvgNumber $Element 'rx'
                    $Context.DrawRoundedRectangle($brush, $null, $bounds, $radius, (Get-SvgNumber $Element 'ry' $radius))
                }
            }
            default { throw "Unsupported SVG element: $($Element.LocalName)" }
        }
    } finally {
        if ($transformed) { $Context.Pop() }
    }
}

function Render-Svg([string]$Path, [int]$Size, [string]$Ink) {
    $svg = [xml](Get-Content -LiteralPath $Path -Raw)
    if ($svg.DocumentElement.GetAttribute('viewBox') -ne '0 0 64 64') { throw 'Expected approved 64 by 64 brand viewBox.' }
    $visual = [System.Windows.Media.DrawingVisual]::new()
    $context = $visual.RenderOpen()
    try {
        $context.PushTransform([System.Windows.Media.ScaleTransform]::new($Size / 64.0, $Size / 64.0))
        Draw-SvgElement $svg.DocumentElement $context $Ink
        $context.Pop()
    } finally { $context.Close() }
    $bitmap = [System.Windows.Media.Imaging.RenderTargetBitmap]::new($Size, $Size, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder = [System.Windows.Media.Imaging.PngBitmapEncoder]::new()
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.MemoryStream]::new()
    try { $encoder.Save($stream); return ,$stream.ToArray() } finally { $stream.Dispose() }
}

function Get-Sha256([byte[]]$Bytes) {
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Write-Icon([string]$Source, [string]$Output, [string]$Ink) {
    $images = [System.Collections.Generic.List[byte[]]]::new()
    foreach ($size in $iconSizes) { $images.Add((Render-Svg $Source $size $Ink)) }
    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$iconSizes.Count)
        $offset = 6 + 16 * $iconSizes.Count
        for ($index = 0; $index -lt $iconSizes.Count; $index++) {
            $size = if ($iconSizes[$index] -eq 256) { 0 } else { $iconSizes[$index] }
            $writer.Write([byte]$size); $writer.Write([byte]$size); $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$images[$index].Length); $writer.Write([uint32]$offset)
            $offset += $images[$index].Length
        }
        foreach ($image in $images) { $writer.Write($image) }
        [System.IO.File]::WriteAllBytes($Output, $stream.ToArray())
    } finally { $writer.Dispose(); $stream.Dispose() }
    $frames = for ($index = 0; $index -lt $iconSizes.Count; $index++) {
        [ordered]@{ size = $iconSizes[$index]; sha256 = Get-Sha256 $images[$index] }
    }
    return [ordered]@{
        path = 'assets/' + [System.IO.Path]::GetFileName($Output)
        source = 'assets/' + [System.IO.Path]::GetFileName($Source)
        ink = $(if ([string]::IsNullOrEmpty($Ink)) { $null } else { $Ink })
        sha256 = Get-Sha256 ([System.IO.File]::ReadAllBytes($Output))
        frames = @($frames)
    }
}

$sources = @(
    @('assets/brand-mark.svg', 'design/prototype/brand-mark.svg'),
    @('assets/brand-mark-mono.svg', 'design/prototype/brand-exploration/frame-mono.svg')
)
$sourceManifest = foreach ($source in $sources) {
    $productionHash = Get-Sha256 ([System.IO.File]::ReadAllBytes((Join-Path $projectRoot $source[0])))
    $approvedHash = Get-Sha256 ([System.IO.File]::ReadAllBytes((Join-Path $projectRoot $source[1])))
    if ($productionHash -ne $approvedHash) { throw "Production SVG differs from approved reference: $($source[0])" }
    [ordered]@{ path = $source[0]; approvedReference = $source[1]; sha256 = $productionHash; approvedSha256 = $approvedHash }
}
$icons = @(
    (Write-Icon (Join-Path $projectRoot 'assets/brand-mark.svg') $IconOutputPath ''),
    (Write-Icon (Join-Path $projectRoot 'assets/brand-mark-mono.svg') (Join-Path $outputDirectory 'dejavu-tray-dark.ico') '#171C17'),
    (Write-Icon (Join-Path $projectRoot 'assets/brand-mark-mono.svg') (Join-Path $outputDirectory 'dejavu-tray-light.ico') '#FFFFFF')
)
$manifest = [ordered]@{ schemaVersion = 1; sizes = $iconSizes; sources = @($sourceManifest); icons = $icons }
[System.IO.File]::WriteAllText((Join-Path $outputDirectory 'brand-icons.json'), ($manifest | ConvertTo-Json -Depth 8) + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Output "Generated three Windows ICOs from approved SVGs, nine sizes each, plus brand-icons.json."
