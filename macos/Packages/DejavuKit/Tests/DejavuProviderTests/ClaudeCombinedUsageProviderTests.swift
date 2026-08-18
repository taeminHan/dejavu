import Foundation
import XCTest
import DejavuApplication
import DejavuDomain
@testable import DejavuProviders

final class ClaudeCombinedUsageProviderTests: XCTestCase {
    func testDisabledPolicyNeverTouchesExtendedProvider() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let extended = ExtendedUsageStub(result: .failure(UnexpectedCall.called))
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: snapshotURL,
                freshnessPolicy: UsageFreshnessPolicy(maximumAgeWithoutReset: 60 * 60 * 24 * 365)
            ),
            extendedProvider: extended,
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()
        let callCount = await extended.callCount()

        XCTAssertEqual(snapshot.source, .statusLine)
        XCTAssertEqual(callCount, 0)
    }

    func testEnabledPolicyUsesExtendedFableSnapshot() async throws {
        let capturedAt = Date(timeIntervalSince1970: 2_000)
        let expected = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 11),
            weekly: UsageLimit(percent: 22),
            fable: UsageLimit(percent: 33),
            source: .oauthUsage,
            capturedAt: capturedAt
        )
        let extended = ExtendedUsageStub(result: .success(expected))
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: URL(fileURLWithPath: "/missing/dejavu-claude-status.json")
            ),
            extendedProvider: extended,
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: true)
        )

        let snapshot = try await provider.fetchUsage()
        let callCount = await extended.callCount()

        XCTAssertEqual(snapshot, expected)
        XCTAssertEqual(callCount, 1)
    }

    func testExtendedFailureFallsBackToOfficialStatusLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: snapshotURL,
                freshnessPolicy: UsageFreshnessPolicy(maximumAgeWithoutReset: 60 * 60 * 24 * 365)
            ),
            extendedProvider: ExtendedUsageStub(
                result: .failure(ClaudeExtendedUsageError.accessDenied)
            ),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: true)
        )

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.source, .statusLine)
        XCTAssertNil(snapshot.fable)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-claude-combined-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}

private enum UnexpectedCall: Error {
    case called
}

private actor ExtendedUsageStub: ClaudeOAuthUsageRequesting {
    private let result: Result<ClaudeUsageSnapshot, Error>
    private var calls = 0

    init(result: Result<ClaudeUsageSnapshot, Error>) {
        self.result = result
    }

    func fetchUsage() async throws -> ClaudeUsageSnapshot {
        calls += 1
        return try result.get()
    }

    func callCount() -> Int { calls }
}
