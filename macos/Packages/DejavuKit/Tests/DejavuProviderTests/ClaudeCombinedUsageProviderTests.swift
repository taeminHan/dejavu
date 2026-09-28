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

    func testExtendedFailureFallsBackToOfficialStatusLine() async throws {
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

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.source, .statusLine)
        XCTAssertNil(snapshot.fable)
    }

    func testStatusLineSnapshotWinsOverDesktopHistory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        // A Desktop sample from the same moment is also current.
        let historyURL = directory.appendingPathComponent("plan-usage-history.json")
        try Data(#"{"version": 2, "samples": [{"t": 1786496400000, "u": {"fh": 5, "sd": 6}}]}"#.utf8)
            .write(to: historyURL)
        let now = try FixtureSupport.date("2026-08-12T01:05:00Z")
        let desktopHistory = ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now })
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL, now: { now }),
            desktopHistoryProvider: desktopHistory,
            extendedProvider: ExtendedUsageStub(result: .failure(UnexpectedCall.called)),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()
        let desktopSnapshot = try await desktopHistory.fetchUsage(now: now)

        XCTAssertEqual(snapshot.source, .statusLine)
        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(desktopSnapshot.source, .desktopHistory)
    }

    func testMissingStatusLineFallsBackToDesktopHistory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeDesktopHistory(in: directory)
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let extended = ExtendedUsageStub(result: .failure(UnexpectedCall.called))
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: directory.appendingPathComponent("claude-status.json"),
                now: { now }
            ),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            extendedProvider: extended,
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()
        let callCount = await extended.callCount()

        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.weekly?.percent, 41)
        XCTAssertNil(snapshot.fable)
        XCTAssertEqual(callCount, 0)
    }

    func testNewerDesktopHistoryWinsOverOlderStatusLineWithFutureReset() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Captured 01:00Z: the 5-hour limit reset at 03:00Z, the weekly one
        // stays valid until 08-19 although Claude Code has not run since.
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let historyURL = directory.appendingPathComponent("plan-usage-history.json")
        try Data(#"{"version": 2, "samples": [{"t": 1786506900000, "u": {"fh": 60, "sd": 55}}]}"#.utf8)
            .write(to: historyURL)
        let now = try FixtureSupport.date("2026-08-12T04:00:00Z")
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL, now: { now }),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertEqual(snapshot.capturedAt, try FixtureSupport.date("2026-08-12T03:55:00Z"))
        XCTAssertEqual(snapshot.fiveHour?.percent, 60)
        XCTAssertEqual(snapshot.weekly?.percent, 55)
    }

    func testOlderDesktopHistoryDoesNotReplaceANewerStatusLine() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        // Desktop sample at 00:55Z, five minutes before the status line.
        let historyURL = directory.appendingPathComponent("plan-usage-history.json")
        try Data(#"{"version": 2, "samples": [{"t": 1786496100000, "u": {"fh": 5, "sd": 6}}]}"#.utf8)
            .write(to: historyURL)
        let now = try FixtureSupport.date("2026-08-12T01:30:00Z")
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL, now: { now }),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.source, .statusLine)
        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.weekly?.percent, 41.25)
    }

    func testExpiredDesktopHistoryKeepsTheClaudeSlotWithoutValues() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let historyURL = try writeDesktopHistory(in: directory)
        // Desktop is running but has not sampled for 45 minutes.
        let now = try FixtureSupport.date("2026-09-28T01:45:00Z")
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL, now: { now }),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertEqual(snapshot.capturedAt, try FixtureSupport.date("2026-09-28T01:00:00Z"))
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.weekly)
        XCTAssertNil(snapshot.fable)
    }

    func testStaleStatusLineFallsBackToDesktopHistory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        let historyURL = try writeDesktopHistory(in: directory)
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(snapshotURL: snapshotURL, now: { now }),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        let snapshot = try await provider.fetchUsage()

        XCTAssertEqual(snapshot.source, .desktopHistory)
    }

    func testDeniedKeychainFallsBackToDesktopHistoryAndKeepsTheReason() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeDesktopHistory(in: directory)
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let policy = ClaudeExtendedAccessPolicy(enabled: true)
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: directory.appendingPathComponent("claude-status.json"),
                now: { now }
            ),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            extendedProvider: ExtendedUsageStub(
                result: .failure(ClaudeExtendedUsageError.accessDenied)
            ),
            accessPolicy: policy
        )

        let snapshot = try await provider.fetchUsage()
        let outcome = await policy.latestOutcome()

        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertNil(snapshot.fable)
        XCTAssertEqual(outcome, .failed(.accessDenied))
    }

    func testAllSourcesFailingReportsTheExtendedReasonFirst() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeDesktopHistory(in: directory)
        // More than a week after the Desktop sample.
        let staleNow = try FixtureSupport.date("2026-10-06T03:00:00Z")
        let retryAt = try FixtureSupport.date("2026-10-06T03:05:00Z")
        let cases: [(ClaudeExtendedUsageError, UsageProviderFailure)] = [
            // Claude Code renews an expired token when it next runs.
            (.credentialExpired, .failed),
            (.credentialUnavailable, .loginRequired),
            (.accessDenied, .unavailable),
            (.rateLimited(retryAt: retryAt), .rateLimited(retryAt: retryAt)),
            (.offline, .offline),
            (.invalidResponse, .failed)
        ]

        for (extendedError, expected) in cases {
            let policy = ClaudeExtendedAccessPolicy(enabled: true)
            let provider = ClaudeCombinedUsageProvider(
                statusLineProvider: ClaudeStatusSnapshotProvider(
                    snapshotURL: directory.appendingPathComponent("claude-status.json"),
                    now: { staleNow }
                ),
                desktopHistoryProvider: ClaudeDesktopHistoryProvider(
                    historyURL: historyURL,
                    now: { staleNow }
                ),
                extendedProvider: ExtendedUsageStub(result: .failure(extendedError)),
                accessPolicy: policy
            )

            do {
                _ = try await provider.fetchUsage()
                XCTFail("Expected every Claude source to fail")
            } catch let failure as UsageProviderFailure {
                XCTAssertEqual(failure, expected)
            }
            let outcome = await policy.latestOutcome()
            XCTAssertEqual(outcome, .failed(extendedError))
        }
    }

    func testAllSourcesFailingWithoutExtendedAccessReportsTheStatusLineReason() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeDesktopHistory(in: directory)
        let snapshotURL = directory.appendingPathComponent("claude-status.json")
        // More than a week after the Desktop sample.
        let staleNow = try FixtureSupport.date("2026-10-06T03:00:00Z")
        let makeProvider = {
            ClaudeCombinedUsageProvider(
                statusLineProvider: ClaudeStatusSnapshotProvider(
                    snapshotURL: snapshotURL,
                    now: { staleNow }
                ),
                desktopHistoryProvider: ClaudeDesktopHistoryProvider(
                    historyURL: historyURL,
                    now: { staleNow }
                ),
                accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
            )
        }

        do {
            _ = try await makeProvider().fetchUsage()
            XCTFail("Expected an idle Desktop without a status line to be unavailable")
        } catch let failure as UsageProviderFailure {
            // Desktop history exists, so Desktop is idle, not signed out.
            XCTAssertEqual(failure, .unavailable)
        }

        try FixtureSupport.data(named: "claude-bridge-complete.json").write(to: snapshotURL)
        do {
            _ = try await makeProvider().fetchUsage()
            XCTFail("Expected a stale status line to be unavailable")
        } catch let failure as UsageProviderFailure {
            XCTAssertEqual(failure, .unavailable)
        }
    }

    func testMissingStatusLineAndMissingDesktopHistoryRequireSignIn() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: directory.appendingPathComponent("claude-status.json"),
                now: { now }
            ),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(
                historyURL: directory.appendingPathComponent("plan-usage-history.json"),
                now: { now }
            ),
            accessPolicy: ClaudeExtendedAccessPolicy(enabled: false)
        )

        do {
            _ = try await provider.fetchUsage()
            XCTFail("Expected a missing status line to require sign-in")
        } catch let failure as UsageProviderFailure {
            XCTAssertEqual(failure, .loginRequired)
        }
    }

    func testExtendedSuccessIsRecordedAndClearedWhenDisabled() async throws {
        let expected = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 11),
            weekly: UsageLimit(percent: 22),
            fable: UsageLimit(percent: 33),
            source: .oauthUsage,
            capturedAt: Date(timeIntervalSince1970: 2_000)
        )
        let policy = ClaudeExtendedAccessPolicy(enabled: true)
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: URL(fileURLWithPath: "/missing/dejavu-claude-status.json")
            ),
            extendedProvider: ExtendedUsageStub(result: .success(expected)),
            accessPolicy: policy
        )

        let initialOutcome = await policy.latestOutcome()
        _ = try await provider.fetchUsage()
        let connectedOutcome = await policy.latestOutcome()
        await policy.setEnabled(false)
        let disabledOutcome = await policy.latestOutcome()
        await policy.setEnabled(true)
        let reenabledOutcome = await policy.latestOutcome()

        XCTAssertNil(initialOutcome)
        XCTAssertEqual(connectedOutcome, .connected)
        XCTAssertNil(disabledOutcome)
        XCTAssertNil(reenabledOutcome)
    }

    func testCancelledExtendedReadIsNotRecordedAndDoesNotFallBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeDesktopHistory(in: directory)
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let policy = ClaudeExtendedAccessPolicy(enabled: true)
        let provider = ClaudeCombinedUsageProvider(
            statusLineProvider: ClaudeStatusSnapshotProvider(
                snapshotURL: directory.appendingPathComponent("claude-status.json"),
                now: { now }
            ),
            desktopHistoryProvider: ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { now }),
            extendedProvider: CancellationReportingExtendedStub(),
            accessPolicy: policy
        )

        let task = Task { try await provider.fetchUsage() }
        task.cancel()
        let result = await task.result
        let outcome = await policy.latestOutcome()

        switch result {
        case .success:
            XCTFail("A cancelled read must not return a fallback snapshot")
        case let .failure(error):
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertNil(outcome)
    }

    private func writeDesktopHistory(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("plan-usage-history.json")
        try FixtureSupport.data(named: "claude-desktop-history-recent.json").write(to: url)
        return url
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

/// Mirrors URLSession, which reports task cancellation as a URL error rather
/// than `CancellationError`.
private struct CancellationReportingExtendedStub: ClaudeOAuthUsageRequesting {
    func fetchUsage() async throws -> ClaudeUsageSnapshot {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        throw URLError(.cancelled)
    }
}
