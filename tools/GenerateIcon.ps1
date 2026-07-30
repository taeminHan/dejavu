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

    $outerMargin = $iconSize * 0.046875
    $markBounds = [System.Drawing.RectangleF]::new(
        [single]$outerMargin,
        [single]$outerMargin,
        [single]($iconSize - 2 * $outerMargin),
        [single]($iconSize - 2 * $outerMargin)
    )
    $backgroundBrush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        $markBounds,
        [System.Drawing.Color]::FromArgb(255, 120, 152, 255),
        [System.Drawing.Color]::FromArgb(255, 82, 111, 232),
        [single]48
    )
    $markPath = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $cornerDiameter = $iconSize * 0.53125
    $markPath.AddArc($markBounds.Left, $markBounds.Top, $cornerDiameter, $cornerDiameter, 180, 90)
    $markPath.AddArc($markBounds.Right - $cornerDiameter, $markBounds.Top, $cornerDiameter, $cornerDiameter, 270, 90)
    $markPath.AddArc($markBounds.Right - $cornerDiameter, $markBounds.Bottom - $cornerDiameter, $cornerDiameter, $cornerDiameter, 0, 90)
    $markPath.AddArc($markBounds.Left, $markBounds.Bottom - $cornerDiameter, $cornerDiameter, $cornerDiameter, 90, 90)
    $markPath.CloseFigure()

    $markPen = [System.Drawing.Pen]::new([System.Drawing.Color]::White, [single][Math]::Max(1.5, $iconSize * 0.09375))
    $markPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $markPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round

    $graphics.FillPath($backgroundBrush, $markPath)
    $graphics.DrawEllipse($markPen, $iconSize * 0.1953125, $iconSize * 0.3359375, $iconSize * 0.453125, $iconSize * 0.453125)
    $graphics.DrawLine($markPen, $iconSize * 0.6484375, $iconSize * 0.2109375, $iconSize * 0.6484375, $iconSize * 0.5625)

    $pngStream = New-Object System.IO.MemoryStream
    $bitmap.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
    $iconImages.Add($pngStream.ToArray())

    $pngStream.Dispose()
    $markPen.Dispose()
    $markPath.Dispose()
    $backgroundBrush.Dispose()
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
