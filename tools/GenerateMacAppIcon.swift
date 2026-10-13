import AppKit
import Foundation

// Regenerates the packaged macOS icon from the repository-owned approved SVG.
// Run from the repository root:
// swift -module-cache-path /tmp/dejavu-icon-cache tools/GenerateMacAppIcon.swift
let arguments = CommandLine.arguments
let source = URL(fileURLWithPath: arguments.count > 1 ? arguments[1] : "design/prototype/brand-mark.svg")
let output = URL(fileURLWithPath: arguments.count > 2 ? arguments[2] : "macos/DejavuMac/Resources/Dejavu.icns")

guard let image = NSImage(contentsOf: source), image.isValid else {
    fatalError("The approved brand SVG could not be rendered.")
}

let staging = FileManager.default.temporaryDirectory
    .appendingPathComponent("dejavu-icon-\(UUID().uuidString)", isDirectory: true)
let iconset = staging.appendingPathComponent("Dejavu.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: staging) }

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Could not allocate an icon representation.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.shouldAntialias = true
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Could not encode an icon representation.")
        }
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
let conversion = Process()
conversion.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
conversion.arguments = ["--convert", "icns", "--output", output.path, iconset.path]
try conversion.run()
conversion.waitUntilExit()
guard conversion.terminationStatus == 0 else { fatalError("iconutil failed.") }
print("Generated \(output.lastPathComponent) from the approved Familiar Paradox SVG (16–1024 px).")
