import Foundation
import XCTest

enum FixtureSupport {
    static func data(named name: String, file: StaticString = #filePath) throws -> Data {
        try Data(contentsOf: directoryURL(file: file).appendingPathComponent(name))
    }

    static func jsonFixtureNames(file: StaticString = #filePath) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL(file: file),
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .map(\.lastPathComponent)
        .sorted()
    }

    private static func directoryURL(file: StaticString) -> URL {
        let testFile = URL(fileURLWithPath: String(describing: file))
        let packageRoot = testFile
            .deletingLastPathComponent() // DejavuProviderTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // DejavuKit
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // repository root
        return packageRoot.appendingPathComponent("contracts/usage/fixtures", isDirectory: true)
    }

    static func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try XCTUnwrap(formatter.date(from: value))
    }
}
