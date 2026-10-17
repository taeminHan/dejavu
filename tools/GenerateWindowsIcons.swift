import AppKit
import CryptoKit
import Foundation

// Generates Windows ICO assets on a Mac; it does not alter the macOS product.
// swift -module-cache-path /tmp/dejavu-windows-icon-cache tools/GenerateWindowsIcons.swift
// Windows maintainers use the SVG-consuming WPF counterpart GenerateIcon.ps1.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
let assets = root.appendingPathComponent("assets", isDirectory: true)
func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func appendLE<T: FixedWidthInteger>(_ number: T, to data: inout Data) {
    var value = number.littleEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}
func sourceManifest(_ production: String, _ reference: String) throws -> [String: Any] {
    let data = try Data(contentsOf: root.appendingPathComponent(production))
    let approved = try Data(contentsOf: root.appendingPathComponent(reference))
    guard data == approved else { fatalError("Production SVG differs from approved reference: \(production)") }
    return ["path": production, "approvedReference": reference, "sha256": hash(data), "approvedSha256": hash(approved)]
}
func render(_ source: String, size: Int, ink: String?) throws -> Data {
    let svgData = try Data(contentsOf: root.appendingPathComponent(source))
    guard var svg = String(data: svgData, encoding: .utf8), svg.contains("viewBox=\"0 0 64 64\"") else {
        fatalError("Expected approved 64 by 64 SVG: \(source)")
    }
    if let ink { svg = svg.replacingOccurrences(of: "currentColor", with: ink) }
    guard let image = NSImage(data: Data(svg.utf8)), image.isValid,
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("Could not allocate SVG renderer.")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.shouldAntialias = true
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed.") }
    return data
}
func writeIcon(_ fileName: String, source: String, ink: String? = nil) throws -> [String: Any] {
    let images = try sizes.map { try render(source, size: $0, ink: ink) }
    var data = Data()
    appendLE(UInt16(0), to: &data); appendLE(UInt16(1), to: &data); appendLE(UInt16(sizes.count), to: &data)
    var offset = 6 + 16 * sizes.count
    for (index, size) in sizes.enumerated() {
        data.append(UInt8(size == 256 ? 0 : size)); data.append(UInt8(size == 256 ? 0 : size))
        data.append(0); data.append(0)
        appendLE(UInt16(1), to: &data); appendLE(UInt16(32), to: &data)
        appendLE(UInt32(images[index].count), to: &data); appendLE(UInt32(offset), to: &data)
        offset += images[index].count
    }
    for image in images { data.append(image) }
    try data.write(to: assets.appendingPathComponent(fileName))
    return ["path": "assets/\(fileName)", "source": source, "ink": ink as Any? ?? NSNull(),
            "sha256": hash(data), "frames": zip(sizes, images).map { ["size": $0, "sha256": hash($1)] as [String: Any] }]
}
let sources = try [
    sourceManifest("assets/brand-mark.svg", "design/prototype/brand-mark.svg"),
    sourceManifest("assets/brand-mark-mono.svg", "design/prototype/brand-exploration/frame-mono.svg")
]
let icons = try [
    writeIcon("dejavu.ico", source: "assets/brand-mark.svg"),
    writeIcon("dejavu-tray-dark.ico", source: "assets/brand-mark-mono.svg", ink: "#171C17"),
    writeIcon("dejavu-tray-light.ico", source: "assets/brand-mark-mono.svg", ink: "#FFFFFF")
]
let manifest: [String: Any] = ["schemaVersion": 1, "sizes": sizes, "sources": sources, "icons": icons]
var json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
json.append(10)
try json.write(to: assets.appendingPathComponent("brand-icons.json"))
print("Generated three Windows ICOs from approved SVGs, nine sizes each, plus brand-icons.json.")
