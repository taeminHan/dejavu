param(
    [string]$IconOutputPath = (Join-Path $PSScriptRoot '..\assets\dejavu.ico')
)

Add-Type -AssemblyName System.Drawing

$iconDirectory = Split-Path -Parent $IconOutputPath
New-Item -ItemType Directory -Force -Path $iconDirectory | Out-Null
$iconSizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
$iconImages = New-Object System.Collections.Generic.List[byte[]]

foreach ($iconSize in $iconSizes) {
    $bitmap = New-Object System.Drawing.Bitmap($iconSize, $iconSize, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 109, 142, 255))
    $markPen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, [Math]::Max(1.25, $iconSize * 0.072))
    $markPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $markPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    $outerMargin = $iconSize * 0.0625
    $graphics.FillEllipse($accentBrush, $outerMargin, $outerMargin, $iconSize - 2 * $outerMargin, $iconSize - 2 * $outerMargin)
    $graphics.DrawArc($markPen, $iconSize * 0.25, $iconSize * 0.25, $iconSize * 0.5, $iconSize * 0.5, -80, 285)
    $graphics.DrawLine($markPen, $iconSize * 0.5, $iconSize * 0.5, $iconSize * 0.69, $iconSize * 0.34)

    $pngStream = New-Object System.IO.MemoryStream
    $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $iconImages.Add($pngStream.ToArray())

    $pngStream.Dispose()
    $markPen.Dispose()
    $accentBrush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$iconFile = [System.IO.File]::Create($IconOutputPath)
$iconWriter = New-Object System.IO.BinaryWriter($iconFile)
$iconWriter.Write([UInt16]0)
$iconWriter.Write([UInt16]1)
$iconWriter.Write([UInt16]$iconSizes.Count)

$dataOffset = 6 + 16 * $iconSizes.Count
for ($iconIndex = 0; $iconIndex -lt $iconSizes.Count; $iconIndex++) {
    $sizeByte = if ($iconSizes[$iconIndex] -eq 256) { 0 } else { $iconSizes[$iconIndex] }
    $iconWriter.Write([Byte]$sizeByte)
    $iconWriter.Write([Byte]$sizeByte)
    $iconWriter.Write([Byte]0)
    $iconWriter.Write([Byte]0)
    $iconWriter.Write([UInt16]1)
    $iconWriter.Write([UInt16]32)
    $iconWriter.Write([UInt32]$iconImages[$iconIndex].Length)
    $iconWriter.Write([UInt32]$dataOffset)
    $dataOffset += $iconImages[$iconIndex].Length
}

foreach ($iconImage in $iconImages) {
    $iconWriter.Write($iconImage)
}

$iconWriter.Dispose()
$iconFile.Dispose()
Write-Output $IconOutputPath
