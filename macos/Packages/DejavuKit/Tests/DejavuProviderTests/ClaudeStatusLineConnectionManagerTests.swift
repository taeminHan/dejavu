import Foundation
import XCTest
@testable import DejavuProviders

final class ClaudeStatusLineConnectionManagerTests: XCTestCase {
    func testInitializationPerformsNoFileSystemAccess() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "dejavu-claude-connect-never-created-\(UUID().uuidString)",
            isDirectory: true
        )
        let paths = Paths(root: root)

        _ = ClaudeStatusLineConnectionManager(configuration: paths.configuration)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testConnectPreservesArbitraryRootAndChainsExistingCommand() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)

        let originalCommand = "printf '%s\\n' \"an existing value\""
        let original: [String: Any] = [
            "env": ["nested": [1, true, NSNull(), "한글"]],
            "largeInteger": NSNumber(value: Int64.max),
            "statusLine": [
                "type": "command",
                "command": originalCommand,
                "padding": 7,
                "extensionData": ["preserve": true]
            ]
        ]
        try writeJSONObject(original, to: paths.settings)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o640],
            ofItemAtPath: paths.settings.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o750],
            ofItemAtPath: paths.settings.deletingLastPathComponent().path
        )

        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
        let result = try await manager.connect()

        XCTAssertEqual(result, .connected)
        let connected = try readJSONObject(at: paths.settings)
        XCTAssertEqual(
            try canonical(connected["env"] as Any),
            try canonical(original["env"] as Any)
        )
        XCTAssertEqual(
            try canonical(connected["largeInteger"] as Any),
            try canonical(original["largeInteger"] as Any)
        )

        let managed = try XCTUnwrap(connected["statusLine"] as? [String: Any])
        XCTAssertEqual(managed["type"] as? String, "command")
        XCTAssertEqual((managed["padding"] as? NSNumber)?.intValue, 7)
        XCTAssertEqual(
            try canonical(managed["extensionData"] as Any),
            try canonical(["preserve": true])
        )
        XCTAssertEqual(
            managed["command"] as? String,
            "exec /usr/bin/env "
                + shellQuote("DEJAVU_CLAUDE_SNAPSHOT_PATH=\(paths.snapshot.path)")
                + " "
                + shellQuote("DEJAVU_CLAUDE_CHAIN_COMMAND=\(originalCommand)")
                + " "
                + shellQuote(paths.installedBridge.path)
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.metadata.path))
        XCTAssertEqual(try Data(contentsOf: paths.installedBridge), try Data(contentsOf: paths.bridge))
        XCTAssertEqual(try permissions(at: paths.installedBridge), 0o700)
        XCTAssertEqual(try permissions(at: paths.settings), 0o640)
        XCTAssertEqual(try permissions(at: paths.metadata), 0o600)
        XCTAssertEqual(try permissions(at: paths.settings.deletingLastPathComponent()), 0o750)
        XCTAssertEqual(try permissions(at: paths.support), 0o700)
    }

    func testDisconnectRestoresOriginalStatusLineAndKeepsConcurrentRootChanges() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        let originalStatusLine: [String: Any] = [
            "type": "command",
            "command": "old-status --json",
            "custom": ["values": [1, 2, 3]]
        ]
        try writeJSONObject(
            ["statusLine": originalStatusLine, "theme": "dark"],
            to: paths.settings
        )
        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
        try await manager.connect()

        var duringConnection = try readJSONObject(at: paths.settings)
        duringConnection["changedWhileConnected"] = ["still": "kept"]
        try writeJSONObject(duringConnection, to: paths.settings)

        let result = try await manager.disconnect()

        XCTAssertEqual(result, .disconnected)
        let restored = try readJSONObject(at: paths.settings)
        XCTAssertEqual(
            try canonical(restored["statusLine"] as Any),
            try canonical(originalStatusLine)
        )
        XCTAssertEqual(restored["theme"] as? String, "dark")
        XCTAssertEqual(
            try canonical(restored["changedWhileConnected"] as Any),
            try canonical(["still": "kept"])
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.metadata.path))
    }

    func testConnectIsIdempotentAndDisconnectRestoresNullStatusLine() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        try writeJSONObject(["statusLine": NSNull(), "keep": 42], to: paths.settings)
        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)

        let firstConnect = try await manager.connect()
        try Data("obsolete installed helper".utf8).write(to: paths.installedBridge)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: paths.installedBridge.path
        )
        let secondConnect = try await manager.connect()
        let firstDisconnect = try await manager.disconnect()
        XCTAssertEqual(firstConnect, .connected)
        XCTAssertEqual(secondConnect, .alreadyConnected)
        XCTAssertEqual(try Data(contentsOf: paths.installedBridge), try Data(contentsOf: paths.bridge))
        XCTAssertEqual(try permissions(at: paths.installedBridge), 0o700)
        XCTAssertEqual(firstDisconnect, .disconnected)

        let restored = try readJSONObject(at: paths.settings)
        XCTAssertTrue(restored.keys.contains("statusLine"))
        XCTAssertTrue(restored["statusLine"] is NSNull)
        XCTAssertEqual((restored["keep"] as? NSNumber)?.intValue, 42)
        let secondDisconnect = try await manager.disconnect()
        XCTAssertEqual(secondDisconnect, .notConnected)
    }

    func testDisconnectRemovesStatusLineAndOriginallyAbsentSettingsFile() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)

        try await manager.connect()
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.settings.path))
        try await manager.disconnect()

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.settings.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.metadata.path))
    }

    func testDisconnectWithoutOriginalStatusLinePreservesOtherSettings() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        try writeJSONObject(["theme": ["name": "system"]], to: paths.settings)
        let original = try readJSONObject(at: paths.settings)
        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)

        try await manager.connect()
        try await manager.disconnect()

        XCTAssertEqual(
            try canonical(try readJSONObject(at: paths.settings)),
            try canonical(original)
        )
    }

    func testConnectCompletesPendingMetadataWriteWithoutLosingRootChanges() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        let originalStatusLine: [String: Any] = [
            "type": "command",
            "command": "previous-status"
        ]
        try writeJSONObject(
            ["statusLine": originalStatusLine, "initial": true],
            to: paths.settings
        )
        let firstManager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
        try await firstManager.connect()

        // Simulate interruption after the recovery metadata became durable but
        // before the managed settings replacement did.
        try writeJSONObject(
            ["statusLine": originalStatusLine, "addedDuringRecovery": 9],
            to: paths.settings
        )
        let recoveredManager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
        let result = try await recoveredManager.connect()

        XCTAssertEqual(result, .connected)
        let recovered = try readJSONObject(at: paths.settings)
        XCTAssertEqual((recovered["addedDuringRecovery"] as? NSNumber)?.intValue, 9)
        let managed = try XCTUnwrap(recovered["statusLine"] as? [String: Any])
        XCTAssertEqual(managed["type"] as? String, "command")
        XCTAssertNotEqual(managed["command"] as? String, "previous-status")
    }

    func testConnectReplacesInstalledBridgeWithoutFollowingSymlinks() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        try FileManager.default.createDirectory(
            at: paths.installedBridge.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("old helper".utf8).write(to: paths.installedBridge)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: paths.installedBridge.path
        )

        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
        try await manager.connect()

        XCTAssertEqual(try Data(contentsOf: paths.installedBridge), try Data(contentsOf: paths.bridge))
        XCTAssertEqual(try permissions(at: paths.installedBridge), 0o700)

        let second = try makePaths()
        defer { try? FileManager.default.removeItem(at: second.root) }
        try makeExecutable(at: second.bridge)
        let target = second.root.appendingPathComponent("outside-helper")
        let sentinel = Data("do not replace".utf8)
        try sentinel.write(to: target)
        try FileManager.default.createDirectory(
            at: second.installedBridge.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: second.installedBridge,
            withDestinationURL: target
        )
        let unsafeManager = ClaudeStatusLineConnectionManager(configuration: second.configuration)
        await assertConnectionError(.metadataStorageUnsafe) {
            try await unsafeManager.connect()
        }
        XCTAssertEqual(try Data(contentsOf: target), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.metadata.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.settings.path))
    }

    func testDisconnectDetectsConflictAndDoesNotOverwriteEitherFile() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        try writeJSONObject(
            ["statusLine": ["type": "command", "command": "original"]],
            to: paths.settings
        )
        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
        try await manager.connect()

        var externallyChanged = try readJSONObject(at: paths.settings)
        externallyChanged["statusLine"] = ["type": "command", "command": "changed elsewhere"]
        try writeJSONObject(externallyChanged, to: paths.settings)
        let beforeDisconnect = try Data(contentsOf: paths.settings)

        await assertConnectionError(.conflict) {
            try await manager.disconnect()
        }

        XCTAssertEqual(try Data(contentsOf: paths.settings), beforeDisconnect)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.metadata.path))
    }

    func testRejectsOversizedMalformedAndNonObjectSettings() async throws {
        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            try FileManager.default.createDirectory(
                at: paths.settings.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 0x20, count: ClaudeStatusLineConnectionManager.maximumSettingsBytes + 1)
                .write(to: paths.settings)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.settingsTooLarge) { try await manager.connect() }
            XCTAssertFalse(FileManager.default.fileExists(atPath: paths.metadata.path))
        }

        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            try FileManager.default.createDirectory(
                at: paths.settings.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("{not-json".utf8).write(to: paths.settings)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.settingsMalformed) { try await manager.connect() }
        }

        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            try FileManager.default.createDirectory(
                at: paths.settings.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("[]".utf8).write(to: paths.settings)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.settingsMalformed) { try await manager.connect() }
        }
    }

    func testRejectsSymlinkAndNonregularSettings() async throws {
        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            let target = paths.root.appendingPathComponent("target-settings.json")
            try writeJSONObject(["safe": true], to: target)
            try FileManager.default.createDirectory(
                at: paths.settings.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: paths.settings, withDestinationURL: target)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.settingsUnsafe) { try await manager.connect() }
        }

        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            try FileManager.default.createDirectory(
                at: paths.settings,
                withIntermediateDirectories: true
            )
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.settingsUnsafe) { try await manager.connect() }
        }
    }

    func testRejectsUnsafeMetadataStorageAndMalformedMetadata() async throws {
        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            let target = paths.root.appendingPathComponent("real-support", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: paths.support.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: paths.support, withDestinationURL: target)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.metadataStorageUnsafe) { try await manager.connect() }
        }

        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
            let target = paths.root.appendingPathComponent("metadata-target")
            try Data("{}".utf8).write(to: target)
            try FileManager.default.createSymbolicLink(at: paths.metadata, withDestinationURL: target)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.metadataStorageUnsafe) { try await manager.connect() }
        }

        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: paths.metadata)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.metadataMalformed) { try await manager.connect() }
        }
    }

    func testRejectsSymlinkNonExecutableBridgeAndUnsafeSnapshot() async throws {
        try await withPaths { paths in
            let target = paths.root.appendingPathComponent("real-bridge")
            try makeExecutable(at: target)
            try FileManager.default.createDirectory(
                at: paths.bridge.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createSymbolicLink(at: paths.bridge, withDestinationURL: target)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.bridgeUnavailable) { try await manager.connect() }
        }

        try await withPaths { paths in
            try FileManager.default.createDirectory(
                at: paths.bridge.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("#!/bin/sh\n".utf8).write(to: paths.bridge)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: paths.bridge.path
            )
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.bridgeUnavailable) { try await manager.connect() }
        }

        try await withPaths { paths in
            try makeExecutable(at: paths.bridge)
            let target = paths.root.appendingPathComponent("snapshot-target")
            try Data().write(to: target)
            try FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: paths.snapshot, withDestinationURL: target)
            let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)
            await assertConnectionError(.snapshotStorageUnsafe) { try await manager.connect() }
        }
    }

    func testRejectsCommandThatCannotBePlacedInAnEnvironmentVariable() async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try makeExecutable(at: paths.bridge)
        try writeJSONObject(
            ["statusLine": ["type": "command", "command": "before\0after"]],
            to: paths.settings
        )
        let manager = ClaudeStatusLineConnectionManager(configuration: paths.configuration)

        await assertConnectionError(.unsupportedExistingCommand) {
            try await manager.connect()
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.metadata.path))
    }

    private func makePaths() throws -> Paths {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "dejavu-claude-connect-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return Paths(root: root)
    }

    private func withPaths(
        _ body: (Paths) async throws -> Void
    ) async throws {
        let paths = try makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        try await body(paths)
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
    }

    private func writeJSONObject(_ value: Any, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url)
    }

    private func readJSONObject(at url: URL) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(value as? [String: Any])
    }

    private func canonical(_ value: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func assertConnectionError(
        _ expected: ClaudeStatusLineConnectionError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as ClaudeStatusLineConnectionError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error type")
        }
    }
}

private struct Paths: Sendable {
    let root: URL
    let settings: URL
    let support: URL
    let bridge: URL
    let snapshot: URL
    let metadata: URL
    let installedBridge: URL

    var configuration: ClaudeStatusLineConnectionConfiguration {
        ClaudeStatusLineConnectionConfiguration(
            settingsURL: settings,
            applicationSupportDirectoryURL: support,
            bridgeExecutableURL: bridge,
            snapshotURL: snapshot
        )
    }

    init(root: URL) {
        self.root = root
        settings = root.appendingPathComponent("home/.claude/settings.json")
        support = root.appendingPathComponent("Library/Application Support/dejavu", isDirectory: true)
        bridge = root.appendingPathComponent("App/Contents/Helpers/dejavu-claude-bridge")
        snapshot = support.appendingPathComponent("claude-status.json")
        metadata = support.appendingPathComponent(
            ClaudeStatusLineConnectionConfiguration.metadataFileName
        )
        installedBridge = support.appendingPathComponent("bin/dejavu-claude-bridge")
    }
}
