import Foundation
import XCTest
@testable import DejavuProviders

final class ClaudeStatusSnapshotProviderTests: XCTestCase {
    func testReadsFreshBridgeSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let provider = ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL)

        let snapshot = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-08-12T01:05:00Z")
        )

        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.weekly?.percent, 41.25)
        XCTAssertNil(snapshot.fable)
    }

    func testRejectsMissingAndOversizedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        let provider = ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL)
        let now = Date(timeIntervalSince1970: 1_000)

        do {
            _ = try await provider.fetchUsage(now: now)
            XCTFail("Expected a missing snapshot failure")
        } catch let error as ClaudeStatusSnapshotProviderError {
            XCTAssertEqual(error, .snapshotUnavailable)
        }

        try Data(repeating: 0x20, count: ClaudeStatusSnapshotProvider.maximumSnapshotBytes + 1)
            .write(to: snapshotURL)
        do {
            _ = try await provider.fetchUsage(now: now)
            XCTFail("Expected a size limit failure")
        } catch let error as ClaudeStatusSnapshotProviderError {
            XCTAssertEqual(error, .snapshotTooLarge)
        }
    }

    func testRejectsSymbolicLinkSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let targetURL = directory.appendingPathComponent("real-snapshot.json")
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: targetURL)
        try FileManager.default.createSymbolicLink(
            at: snapshotURL,
            withDestinationURL: targetURL
        )
        let provider = ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL)

        do {
            _ = try await provider.fetchUsage(
                now: try FixtureSupport.date("2026-08-12T01:05:00Z")
            )
            XCTFail("Expected a symbolic-link snapshot failure")
        } catch let error as ClaudeStatusSnapshotProviderError {
            XCTAssertEqual(error, .snapshotUnavailable)
        }
    }

    func testRejectsExpiredSnapshotWithoutReturningStalePercent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let provider = ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL)

        do {
            _ = try await provider.fetchUsage(
                now: try FixtureSupport.date("2026-08-20T01:00:00Z")
            )
            XCTFail("Expected an expired snapshot failure")
        } catch let error as ClaudeStatusSnapshotProviderError {
            XCTAssertEqual(error, .snapshotStale)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-claude-provider-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
