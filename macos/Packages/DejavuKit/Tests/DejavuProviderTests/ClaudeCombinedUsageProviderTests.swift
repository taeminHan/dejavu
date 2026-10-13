import Foundation
import XCTest
import DejavuApplication
import DejavuDomain
@testable import DejavuProviders

final class ClaudeCombinedUsageProviderTests: XCTestCase {
    func testCancelledOldConfigurationCannotChangeCurrentAccessPolicy() async {
        let policy = ClaudeExtendedAccessPolicy(enabled: true)
        let oldConfiguration = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await policy.setEnabled(false)
        }
        await oldConfiguration.value
        let isEnabled = await policy.isEnabled()
        XCTAssertTrue(isEnabled)
    }

    func testDisabledPolicyNeverTouchesExtendedProvider() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let now = try FixtureSupport.date("2026-08-12T01:05:00Z")
        let extended = ExtendedUsageStub(result: .failure(UnexpectedCall.called))
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: snapshotURL,
                now: { now }
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

    func testEnabledPolicyFailureNeverFallsBackToUnattributedStatusLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let now = try FixtureSupport.date("2026-08-12T01:05:00Z")
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: snapshotURL,
                now: { now }
            ),
            extendedProvider: ExtendedUsageStub(
                result: .failure(ClaudeExtendedUsageError.accessDenied)
            ),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: true)
        )

        do { _ = try await provider.fetchUsage(); XCTFail("Expected selected identity's failure") }
        catch { XCTAssertEqual(error as? UsageProviderFailure, .permissionDenied) }
    }

    func testMissingFirstSnapshotWaitsForDataRatherThanRequestingLogin() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: directory.appendingPathComponent("missing.json")),
            extendedProvider: ExtendedUsageStub(result: .failure(UnexpectedCall.called)),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )
        do { _ = try await provider.fetchUsage(); XCTFail("Expected first data wait") }
        catch { XCTAssertEqual(error as? UsageProviderFailure, .waitingForData) }
    }

    func testSelectedIdentityPreservesOriginalExtendedFailureAndRetryDate() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let retryAt = Date(timeIntervalSince1970: 2_000)
        let cases: [(ClaudeExtendedUsageError, UsageProviderFailure)] = [
            (.offline, .offline), (.unauthorized, .loginRequired),
            (.accessDenied, .permissionDenied), (.tokenRefreshPending, .tokenRefreshPending),
            (.serverError, .serverFailed), (.invalidResponse, .responseChanged),
            (.responseTooLarge, .responseChanged),
            (.rateLimited(retryAt: retryAt), .rateLimited(retryAt: retryAt))
        ]
        for (failure, expected) in cases {
            let provider = ClaudeCombinedUsageProvider(
                statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: directory.appendingPathComponent("missing.json")),
                extendedProvider: ExtendedUsageStub(result: .failure(failure)),
                accessPolicy: ClaudeExtendedAccessPolicy(enabled: true)
            )
            do { _ = try await provider.fetchUsage(); XCTFail("Expected original failure") }
            catch { XCTAssertEqual(error as? UsageProviderFailure, expected) }
        }
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
