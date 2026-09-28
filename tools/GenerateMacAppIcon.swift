// Renders Dejavu's own mark (assets/brand-mark.svg) as the macOS app icon.
//
// Usage:
//   swift tools/GenerateMacAppIcon.swift macos/DejavuMac/Resources/BrandAssets.xcassets/AppIcon.appiconset
//
// The artwork follows the macOS app icon grid: a transparent 1024 x 1024
// canvas, an 824 x 824 continuous-corner body centred with a 100 px margin and
// a subtle drop shadow that stays inside that margin. The ring and the line
// keep the SVG geometry, mapped from the SVG body onto the grid body. Every
// pixel size is drawn natively from the vector geometry; no PNG is resampled.
// Output is sRGB, 8-bit RGBA PNG. Only CoreGraphics and ImageIO are used.

import CoreGraphics
import Foundation
import ImageIO

struct GeneratorError: Error, CustomStringConvertible {
    let description: String
}

/// macOS app icon grid, expressed on the 1024-unit canvas.
enum IconGrid {
    static let canvas: CGFloat = 1024
    static let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    static let cornerRadius: CGFloat = 185.4
    /// Corner smoothing that approximates Apple's continuous corner curve.
    static let cornerSmoothing: CGFloat = 0.6
    static let shadowOffsetY: CGFloat = 10
    static let shadowBlur: CGFloat = 20
    static let shadowAlpha: CGFloat = 0.25
    /// Keeps the ring and line legible at 16 px, like tools/GenerateIcon.ps1.
    static let minimumStrokePixels: CGFloat = 1.5
}

/// Geometry of assets/brand-mark.svg in its 64-unit viewBox.
enum BrandMark {
    static let body = CGRect(x: 3, y: 3, width: 58, height: 58)
    static let gradientStart = CGPoint(x: 10, y: 8)
    static let gradientEnd = CGPoint(x: 54, y: 58)
    static let gradientStartColor = (red: 0x78, green: 0x98, blue: 0xFF)
    static let gradientEndColor = (red: 0x52, green: 0x6F, blue: 0xE8)
    static let ringCenter = CGPoint(x: 27, y: 36)
    static let ringRadius: CGFloat = 14.5
    static let lineX: CGFloat = 41.5
    static let lineTop: CGFloat = 13.5
    static let lineBottom: CGFloat = 36
    static let strokeWidth: CGFloat = 6

    /// Icon grid units per SVG unit.
    static var gridScale: CGFloat { IconGrid.body.width / body.width }

    static func gridPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: IconGrid.body.minX + (point.x - body.minX) * gridScale,
            y: IconGrid.body.minY + (point.y - body.minY) * gridScale
        )
    }
}

struct IconFile {
    let name: String
    let pixelSize: Int
    let scale: Int
}

let iconFiles: [IconFile] = [
    IconFile(name: "icon_16x16.png", pixelSize: 16, scale: 1),
    IconFile(name: "icon_16x16@2x.png", pixelSize: 32, scale: 2),
    IconFile(name: "icon_32x32.png", pixelSize: 32, scale: 1),
    IconFile(name: "icon_32x32@2x.png", pixelSize: 64, scale: 2),
    IconFile(name: "icon_128x128.png", pixelSize: 128, scale: 1),
    IconFile(name: "icon_128x128@2x.png", pixelSize: 256, scale: 2),
    IconFile(name: "icon_256x256.png", pixelSize: 256, scale: 1),
    IconFile(name: "icon_256x256@2x.png", pixelSize: 512, scale: 2),
    IconFile(name: "icon_512x512.png", pixelSize: 512, scale: 1),
    IconFile(name: "icon_512x512@2x.png", pixelSize: 1024, scale: 2),
]

/// A rounded rectangle whose corners blend into the edges with curvature
/// continuity: each corner is a short circular arc between two cubic
/// transitions, following the corner-smoothing construction used by design
/// tools to approximate Apple's continuous corners.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat, smoothing: CGFloat) throws -> CGPath {
    let degree = CGFloat.pi / 180
    let cornerLength = (1 + smoothing) * radius
    guard cornerLength * 2 <= min(rect.width, rect.height) else {
        throw GeneratorError(description: "Corner radius \(radius) is too large for \(rect.size).")
    }

    let arcMeasure = 90 * (1 - smoothing) * degree
    let arcSectionLength = sin(arcMeasure / 2) * radius * CGFloat(2).squareRoot()
    let angleAlpha = (90 * degree - arcMeasure) / 2
    let transitionDistance = radius * tan(angleAlpha / 2)
    let angleBeta = 45 * smoothing * degree
    let c = transitionDistance * cos(angleBeta)
    let d = c * tan(angleBeta)
    let b = (cornerLength - arcSectionLength - c - d) / 3
    let a = 2 * b
    let arcHandle = 4 / 3 * tan(arcMeasure / 4) * radius
    let tangentLength = (c * c + d * d).squareRoot()
    let arcStart = cornerLength - a - b - c

    // Corner-local coordinates: `back` runs from the corner vertex against the
    // incoming edge, `forward` runs from the vertex along the outgoing edge.
    let corners: [(vertex: CGPoint, incoming: CGVector, outgoing: CGVector)] = [
        (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
        (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
        (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
        (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
    ]

    let path = CGMutablePath()
    for (index, corner) in corners.enumerated() {
        func point(back: CGFloat, forward: CGFloat) -> CGPoint {
            CGPoint(
                x: corner.vertex.x - back * corner.incoming.dx + forward * corner.outgoing.dx,
                y: corner.vertex.y - back * corner.incoming.dy + forward * corner.outgoing.dy
            )
        }

        let entry = point(back: cornerLength, forward: 0)
        if index == 0 {
            path.move(to: entry)
        } else {
            path.addLine(to: entry)
        }
        path.addCurve(
            to: point(back: arcStart, forward: d),
            control1: point(back: cornerLength - a, forward: 0),
            control2: point(back: cornerLength - a - b, forward: 0)
        )
        path.addCurve(
            to: point(back: d, forward: arcStart),
            control1: point(back: arcStart - arcHandle * c / tangentLength, forward: d + arcHandle * d / tangentLength),
            control2: point(back: d + arcHandle * d / tangentLength, forward: arcStart - arcHandle * c / tangentLength)
        )
        path.addCurve(
            to: point(back: 0, forward: cornerLength),
            control1: point(back: 0, forward: cornerLength - a - b),
            control2: point(back: 0, forward: cornerLength - a)
        )
    }
    path.closeSubpath()
    return path
}

func srgbColor(_ components: (red: Int, green: Int, blue: Int), alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat(components.red) / 255,
        green: CGFloat(components.green) / 255,
        blue: CGFloat(components.blue) / 255,
        alpha: alpha
    )
}

func renderIcon(pixelSize: Int, colorSpace: CGColorSpace) throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw GeneratorError(description: "Could not create a \(pixelSize) px bitmap context.")
    }
    guard let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [srgbColor(BrandMark.gradientStartColor), srgbColor(BrandMark.gradientEndColor)] as CFArray,
        locations: [0, 1]
    ) else {
        throw GeneratorError(description: "Could not create the body gradient.")
    }

    let pixelsPerUnit = CGFloat(pixelSize) / IconGrid.canvas
    context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    // Design space: 1024 units, origin at the top left and y pointing down,
    // matching the SVG coordinate system.
    context.translateBy(x: 0, y: CGFloat(pixelSize))
    context.scaleBy(x: pixelsPerUnit, y: -pixelsPerUnit)

    let body = try continuousRoundedRect(
        IconGrid.body,
        radius: IconGrid.cornerRadius,
        smoothing: IconGrid.cornerSmoothing
    )

    // Shadow offset and blur are specified in device pixels, where y points up.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -IconGrid.shadowOffsetY * pixelsPerUnit),
        blur: IconGrid.shadowBlur * pixelsPerUnit,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: IconGrid.shadowAlpha)
    )
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.saveGState()
    context.addPath(body)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: BrandMark.gridPoint(BrandMark.gradientStart),
        end: BrandMark.gridPoint(BrandMark.gradientEnd),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()
    context.endTransparencyLayer()
    context.restoreGState()

    let strokeWidth = max(
        BrandMark.strokeWidth * BrandMark.gridScale,
        IconGrid.minimumStrokePixels / pixelsPerUnit
    )
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.setLineWidth(strokeWidth)
    context.setLineCap(.round)

    let ringCenter = BrandMark.gridPoint(BrandMark.ringCenter)
    let ringRadius = BrandMark.ringRadius * BrandMark.gridScale
    context.strokeEllipse(in: CGRect(
        x: ringCenter.x - ringRadius,
        y: ringCenter.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
    ))

    context.move(to: BrandMark.gridPoint(CGPoint(x: BrandMark.lineX, y: BrandMark.lineTop)))
    context.addLine(to: BrandMark.gridPoint(CGPoint(x: BrandMark.lineX, y: BrandMark.lineBottom)))
    context.strokePath()

    guard let image = context.makeImage() else {
        throw GeneratorError(description: "Could not create the \(pixelSize) px image.")
    }
    return image
}

func writePNG(_ image: CGImage, to url: URL, scale: Int) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw GeneratorError(description: "Could not create \(url.lastPathComponent).")
    }
    let dotsPerInch = 72 * scale
    let properties = [
        kCGImagePropertyDPIWidth as String: dotsPerInch,
        kCGImagePropertyDPIHeight as String: dotsPerInch,
    ] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
        throw GeneratorError(description: "Could not write \(url.lastPathComponent).")
    }
}

func generate(into directory: URL) throws {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw GeneratorError(description: "The sRGB color space is unavailable.")
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var renderedImages: [Int: CGImage] = [:]
    for file in iconFiles {
        let image: CGImage
        if let rendered = renderedImages[file.pixelSize] {
            image = rendered
        } else {
            image = try renderIcon(pixelSize: file.pixelSize, colorSpace: colorSpace)
            renderedImages[file.pixelSize] = image
        }
        try writePNG(image, to: directory.appendingPathComponent(file.name), scale: file.scale)
        print("\(file.name) \(file.pixelSize)x\(file.pixelSize)")
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift tools/GenerateMacAppIcon.swift <output-dir>\n".utf8))
    exit(64)
}

do {
    try generate(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
} catch {
    FileHandle.standardError.write(Data("GenerateMacAppIcon: \(error)\n".utf8))
    exit(1)
}
