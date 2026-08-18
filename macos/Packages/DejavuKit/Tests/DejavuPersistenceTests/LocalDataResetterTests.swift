import Foundation
import XCTest
@testable import DejavuPersistence

final class LocalDataResetterTests: XCTestCase {
    func testRemovesOnlyAllowListedLocalFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("dejavu", isDirectory: true)
        let bin = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let removable = [
            "settings.json",
            "status.json",
            "claude-status.json",
            "claude-status-line-connection.json",
            "diagnostics.log",
            "diagnostics.previous.log",
            "settings.corrupt-20260818-120000.json"
        ]
        for name in removable {
            try Data("safe".utf8).write(to: directory.appendingPathComponent(name))
        }
        try Data("helper".utf8).write(
            to: bin.appendingPathComponent("dejavu-claude-bridge")
        )
        try Data("keep".utf8).write(to: directory.appendingPathComponent("user-note.txt"))

        let removed = try LocalDataResetter(directoryURL: directory).reset()

        XCTAssertEqual(
            removed,
            (removable + ["bin/dejavu-claude-bridge"]).sorted()
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("user-note.txt").path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: bin.path))
    }

    func testRejectsBroadAndUnexpectedDirectories() {
        let unsafeURLs = [
            URL(fileURLWithPath: "/"),
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.temporaryDirectory.appendingPathComponent("other")
        ]
        for url in unsafeURLs {
            XCTAssertThrowsError(try LocalDataResetter(directoryURL: url).reset()) { error in
                XCTAssertEqual(error as? LocalDataResetError, .unsafeDirectory)
            }
        }
    }

    func testDoesNotFollowASymlinkedBinDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = root.appendingPathComponent("dejavu", isDirectory: true)
        let external = root.appendingPathComponent("external", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let externalHelper = external.appendingPathComponent("dejavu-claude-bridge")
        try Data("keep".utf8).write(to: externalHelper)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("bin"),
            withDestinationURL: external
        )

        XCTAssertEqual(
            try LocalDataResetter(directoryURL: directory).reset(),
            ["bin"]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalHelper.path))
    }
}
