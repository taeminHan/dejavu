import Darwin
import Foundation
import XCTest
import DejavuApplication
import DejavuDomain
@testable import DejavuProviders

final class ClaudeDesktopHistoryParserTests: XCTestCase {
    private let parser = ClaudeDesktopHistoryParser()

    func testUsesLatestSampleByCaptureTimeAndIgnoresUnknownKeys() throws {
        let snapshot = try parser.parse(
            FixtureSupport.data(named: "claude-desktop-history-recent.json")
        )

        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertEqual(snapshot.capturedAt, try FixtureSupport.date("2026-09-28T01:00:00Z"))
        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.weekly?.percent, 41)
        XCTAssertNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNil(snapshot.weekly?.resetsAt)
        XCTAssertNil(snapshot.fable)
    }

    func testSkipsMalformedSamplesAndKeepsIndependentWindows() throws {
        let snapshot = try parser.parse(
            FixtureSupport.data(named: "claude-desktop-history-lossy.json")
        )

        XCTAssertEqual(snapshot.capturedAt, try FixtureSupport.date("2026-09-28T01:00:00Z"))
        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.weekly?.percent, 44)
        XCTAssertNil(snapshot.fable)
    }

    func testLatestSampleWithoutUsageIsNotReplacedByAnOlderSample() throws {
        XCTAssertThrowsError(
            try parser.parse(FixtureSupport.data(named: "claude-desktop-history-no-usage.json"))
        ) { error in
            XCTAssertEqual(error as? ClaudeDesktopHistoryParserError, .noUsableSample)
        }
    }

    func testRejectsMalformedAndEmptyHistories() {
        let payloads = [
            #"{"version": 2, "samples": ["#,
            #"{"version": 2}"#,
            #"{"version": 2, "samples": {}}"#,
            #"{"version": 2, "samples": []}"#,
            #"[]"#
        ]

        for payload in payloads {
            XCTAssertThrowsError(try parser.parse(Data(payload.utf8)), payload)
        }
    }
}

final class ClaudeDesktopHistoryProviderTests: XCTestCase {
    func testReadsRecentHistoryWithoutFableOrResetTimes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)

        let snapshot = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:10:00Z")
        )

        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.weekly?.percent, 41)
        XCTAssertNil(snapshot.fiveHour?.resetsAt)
        XCTAssertNil(snapshot.weekly?.resetsAt)
        XCTAssertNil(snapshot.fable)
    }

    func testAcceptsSampleValuesUpToFortyMinutesOld() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)

        let boundary = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:40:00Z")
        )
        XCTAssertEqual(boundary.fiveHour?.percent, 23.5)
        XCTAssertEqual(boundary.weekly?.percent, 41)

        let expired = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:40:01Z")
        )
        try assertPlaceholder(expired, capturedAt: "2026-09-28T01:00:00Z")
    }

    func testOlderSampleKeepsTheSlotWithoutValuesForAWeek() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)

        // Desktop can skip samples for longer than the window while it runs.
        let idle = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:45:00Z")
        )
        try assertPlaceholder(idle, capturedAt: "2026-09-28T01:00:00Z")

        let weekOld = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-10-05T01:00:00Z")
        )
        try assertPlaceholder(weekOld, capturedAt: "2026-09-28T01:00:00Z")

        await assertFailure(
            .historyStale,
            provider: provider,
            now: try FixtureSupport.date("2026-10-05T01:00:01Z")
        )
    }

    func testRejectsSampleMoreThanTwoMinutesAheadOfTheClock() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)

        let withinSkew = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T00:58:00Z")
        )
        XCTAssertEqual(withinSkew.fiveHour?.percent, 23.5)

        do {
            _ = try await provider.fetchUsage(
                now: try FixtureSupport.date("2026-09-28T00:57:59Z")
            )
            XCTFail("Expected a future-skewed Desktop history failure")
        } catch let error as ClaudeDesktopHistoryProviderError {
            XCTAssertEqual(error, .historyStale)
        }
    }

    func testRejectsMissingMalformedOversizedAndSymbolicLinkHistory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let historyURL = directory.appendingPathComponent("plan-usage-history.json")

        await assertFailure(
            .historyUnavailable,
            provider: ClaudeDesktopHistoryProvider(historyURL: historyURL),
            now: now
        )

        try Data(#"{"version": 2, "samples": ["#.utf8).write(to: historyURL)
        await assertFailure(
            .invalidHistory,
            provider: ClaudeDesktopHistoryProvider(historyURL: historyURL),
            now: now
        )

        try FixtureSupport.data(named: "claude-desktop-history-recent.json").write(to: historyURL)
        await assertFailure(
            .historyTooLarge,
            provider: ClaudeDesktopHistoryProvider(historyURL: historyURL, maximumBytes: 64),
            now: now
        )

        let linkURL = directory.appendingPathComponent("linked-history.json")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: historyURL)
        await assertFailure(
            .historyUnavailable,
            provider: ClaudeDesktopHistoryProvider(historyURL: linkURL),
            now: now
        )
    }

    func testUnchangedHistoryReusesTheParsedSampleWithoutRereading() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)
        let now = try FixtureSupport.date("2026-09-28T01:10:00Z")
        let original = try fileTimes(at: historyURL)

        let first = try await provider.fetchUsage(now: now)
        // Same size and modification time, different bytes: only a reopen
        // could observe the new percentages.
        let fixture = try FixtureSupport.data(named: "claude-desktop-history-recent.json")
        let replaced = try XCTUnwrap(String(data: fixture, encoding: .utf8))
            .replacingOccurrences(of: #""fh": 23.5"#, with: #""fh": 77.5"#)
        try Data(replaced.utf8).write(to: historyURL)
        try restoreFileTimes(original, at: historyURL)
        let second = try await provider.fetchUsage(now: now)

        XCTAssertEqual(first.fiveHour?.percent, 23.5)
        XCTAssertEqual(second, first)
    }

    func testChangedHistoryIsReadAgain() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)
        let now = try FixtureSupport.date("2026-09-28T01:20:00Z")

        _ = try await provider.fetchUsage(now: now)
        try Data(#"""
        {
          "version": 2,
          "samples": [
            { "t": 1790558100000, "u": { "fh": 31, "sd": 45 } }
          ]
        }
        """#.utf8).write(to: historyURL)
        let updated = try await provider.fetchUsage(now: now)

        XCTAssertEqual(updated.capturedAt, try FixtureSupport.date("2026-09-28T01:15:00Z"))
        XCTAssertEqual(updated.fiveHour?.percent, 31)
        XCTAssertEqual(updated.weekly?.percent, 45)
    }

    func testRecentCachedSampleCoversAPartialWriteOrReplacementUntilItExpires() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let provider = ClaudeDesktopHistoryProvider(historyURL: historyURL)

        let first = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:10:00Z")
        )
        try Data(#"{"version": 2, "samples": [{"t": 17905"#.utf8).write(to: historyURL)
        let duringWrite = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:11:00Z")
        )
        try FileManager.default.removeItem(at: historyURL)
        let duringReplace = try await provider.fetchUsage(
            now: try FixtureSupport.date("2026-09-28T01:12:00Z")
        )

        XCTAssertEqual(duringWrite, first)
        XCTAssertEqual(duringReplace, first)
        await assertFailure(
            .historyUnavailable,
            provider: provider,
            now: try FixtureSupport.date("2026-09-28T01:40:01Z")
        )
    }

    func testProviderAdapterUsesInjectedClockAndNeverReportsLoginRequired() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = try writeFixture("claude-desktop-history-recent.json", in: directory)
        let freshNow = try FixtureSupport.date("2026-09-28T01:05:00Z")
        let idleNow = try FixtureSupport.date("2026-09-28T03:00:00Z")
        let staleNow = try FixtureSupport.date("2026-10-06T00:00:00Z")

        let snapshot = try await ClaudeDesktopHistoryProvider(
            historyURL: historyURL,
            now: { freshNow }
        ).fetchUsage()
        XCTAssertEqual(snapshot.source, .desktopHistory)
        XCTAssertEqual(snapshot.weekly?.percent, 41)

        let idle = try await ClaudeDesktopHistoryProvider(
            historyURL: historyURL,
            now: { idleNow }
        ).fetchUsage()
        try assertPlaceholder(idle, capturedAt: "2026-09-28T01:00:00Z")

        for provider in [
            ClaudeDesktopHistoryProvider(historyURL: historyURL, now: { staleNow }),
            ClaudeDesktopHistoryProvider(
                historyURL: directory.appendingPathComponent("missing.json"),
                now: { freshNow }
            )
        ] {
            do {
                _ = try await provider.fetchUsage()
                XCTFail("Expected an unavailable Desktop history")
            } catch let failure as UsageProviderFailure {
                XCTAssertEqual(failure, .unavailable)
            }
        }
    }

    func testDefaultHistoryURLPointsAtClaudeApplicationSupport() {
        let applicationSupport = URL(fileURLWithPath: "/Users/example/Library/Application Support")

        XCTAssertEqual(
            ClaudeDesktopHistoryProvider.defaultHistoryURL(
                applicationSupportDirectory: applicationSupport
            ).path,
            "/Users/example/Library/Application Support/Claude/plan-usage-history.json"
        )
    }

    private func assertPlaceholder(
        _ snapshot: ClaudeUsageSnapshot,
        capturedAt: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(snapshot.source, .desktopHistory, file: file, line: line)
        XCTAssertEqual(snapshot.capturedAt, try FixtureSupport.date(capturedAt), file: file, line: line)
        XCTAssertNil(snapshot.fiveHour, file: file, line: line)
        XCTAssertNil(snapshot.weekly, file: file, line: line)
        XCTAssertNil(snapshot.fable, file: file, line: line)
    }

    private func assertFailure(
        _ expected: ClaudeDesktopHistoryProviderError,
        provider: ClaudeDesktopHistoryProvider,
        now: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await provider.fetchUsage(now: now)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ClaudeDesktopHistoryProviderError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error \(error)", file: file, line: line)
        }
    }

    private func writeFixture(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("plan-usage-history.json")
        try FixtureSupport.data(named: name).write(to: url)
        return url
    }

    private func fileTimes(at url: URL) throws -> [timespec] {
        var information = stat()
        let status = url.path.withCString { Darwin.lstat($0, &information) }
        XCTAssertEqual(status, 0)
        return [information.st_atimespec, information.st_mtimespec]
    }

    private func restoreFileTimes(_ times: [timespec], at url: URL) throws {
        var times = times
        let status = url.path.withCString { Darwin.utimensat(AT_FDCWD, $0, &times, 0) }
        XCTAssertEqual(status, 0)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dejavu-claude-desktop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }
}
