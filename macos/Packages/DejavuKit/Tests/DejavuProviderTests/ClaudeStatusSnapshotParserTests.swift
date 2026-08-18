import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class ClaudeStatusLineParserTests: XCTestCase {
    func testExtractsOnlySupportedUsageFields() throws {
        let capturedAt = try FixtureSupport.date("2026-08-12T01:00:00Z")
        let snapshot = try ClaudeStatusLineParser().parse(
            FixtureSupport.data(named: "claude-status-line-complete.json"),
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_786_503_600))
        XCTAssertEqual(snapshot.weekly?.percent, 41.25)
        XCTAssertEqual(snapshot.weekly?.resetsAt, Date(timeIntervalSince1970: 1_787_108_400))
        XCTAssertNil(snapshot.fable)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
    }

    func testAcceptsAbsentAndIndependentWindows() throws {
        let capturedAt = try FixtureSupport.date("2026-08-12T01:00:00Z")
        let noLimits = try ClaudeStatusLineParser().parse(
            Data(#"{}"#.utf8),
            capturedAt: capturedAt
        )
        let weeklyOnly = try ClaudeStatusLineParser().parse(
            Data(#"""
            {
              "rate_limits": {
                "seven_day": { "used_percentage": 12.5, "resets_at": null }
              }
            }
            """#.utf8),
            capturedAt: capturedAt
        )

        XCTAssertNil(noLimits.fiveHour)
        XCTAssertNil(noLimits.weekly)
        XCTAssertNil(noLimits.fable)
        XCTAssertNil(weeklyOnly.fiveHour)
        XCTAssertEqual(weeklyOnly.weekly?.percent, 12.5)
        XCTAssertNil(weeklyOnly.fable)
        XCTAssertNil(weeklyOnly.weekly?.resetsAt)
    }
}

final class ClaudeStatusSnapshotParserTests: XCTestCase {
    private let parser = ClaudeStatusSnapshotParser()

    func testParsesCompleteBridgeSnapshot() throws {
        let snapshot = try parser.parse(
            FixtureSupport.data(named: "claude-bridge-complete.json")
        )

        XCTAssertEqual(snapshot.fiveHour?.percent, 23.5)
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, try FixtureSupport.date("2026-08-12T03:00:00Z"))
        XCTAssertEqual(snapshot.weekly?.percent, 41.25)
        XCTAssertEqual(snapshot.weekly?.resetsAt, try FixtureSupport.date("2026-08-19T03:00:00Z"))
        XCTAssertNil(snapshot.fable)
        XCTAssertEqual(snapshot.capturedAt, try FixtureSupport.date("2026-08-12T01:00:00Z"))
    }

    func testAcceptsEachWindowIndependently() throws {
        let fiveHourOnly = try parser.parse(
            FixtureSupport.data(named: "claude-bridge-five-hour-only.json")
        )
        let weeklyOnly = try parser.parse(
            FixtureSupport.data(named: "claude-bridge-seven-day-only.json")
        )

        XCTAssertEqual(fiveHourOnly.fiveHour?.percent, 18)
        XCTAssertNil(fiveHourOnly.fiveHour?.resetsAt)
        XCTAssertNil(fiveHourOnly.weekly)
        XCTAssertNil(weeklyOnly.fiveHour)
        XCTAssertEqual(weeklyOnly.weekly?.percent, 62.75)
    }

    func testMissingRateLimitsAreUnavailableRatherThanZero() throws {
        let snapshot = try parser.parse(
            FixtureSupport.data(named: "claude-bridge-no-rate-limits.json")
        )

        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.weekly)
    }

    func testPreservesOutOfRangePercentageForSingleDisplayClamp() throws {
        let data = Data(#"""
        {
          "schema_version": 1,
          "captured_at": "2026-08-12T01:00:00Z",
          "rate_limits": {
            "five_hour": { "used_percentage": 130, "resets_at": null }
          }
        }
        """#.utf8)

        let snapshot = try parser.parse(data)
        XCTAssertEqual(snapshot.fiveHour?.percent, 130)
    }

    func testRejectsUnsupportedSchemaVersion() throws {
        let data = Data(#"""
        {
          "schema_version": 2,
          "captured_at": "2026-08-12T01:00:00Z"
        }
        """#.utf8)

        XCTAssertThrowsError(try parser.parse(data)) { error in
            XCTAssertEqual(
                error as? ClaudeStatusSnapshotParserError,
                .unsupportedSchemaVersion(2)
            )
        }
    }

    func testRejectsMalformedPayload() {
        XCTAssertThrowsError(
            try parser.parse(Data(#"{"schema_version":1,"captured_at":"not-a-date"}"#.utf8))
        )
    }
}

final class ClaudeProviderFreshnessIntegrationTests: XCTestCase {
    private let policy = UsageFreshnessPolicy(
        maximumAgeWithoutReset: 15 * 60,
        maximumFutureClockSkew: 5 * 60
    )

    func testExpiresEachWindowAtItsOwnReset() throws {
        let capture = try FixtureSupport.date("2026-08-12T01:00:00Z")
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(
                percent: 20,
                resetsAt: try FixtureSupport.date("2026-08-12T02:00:00Z")
            ),
            weekly: UsageLimit(
                percent: 40,
                resetsAt: try FixtureSupport.date("2026-08-19T01:00:00Z")
            ),
            fable: UsageLimit(
                percent: 15,
                resetsAt: try FixtureSupport.date("2026-08-12T01:30:00Z")
            ),
            source: .statusLine,
            capturedAt: capture
        )

        let fresh = try XCTUnwrap(policy.freshClaudeSnapshot(
            from: snapshot,
            now: FixtureSupport.date("2026-08-12T02:00:00Z")
        ))
        XCTAssertNil(fresh.fiveHour)
        XCTAssertEqual(fresh.weekly?.percent, 40)
        XCTAssertNil(fresh.fable)
    }

    func testExpiresResetlessWindowAfterTTL() throws {
        let capture = try FixtureSupport.date("2026-08-12T01:00:00Z")
        let limit = UsageLimit(percent: 20, resetsAt: nil)

        XCTAssertNotNil(policy.freshLimit(
            limit,
            capturedAt: capture,
            now: try FixtureSupport.date("2026-08-12T01:15:00Z")
        ))
        XCTAssertNil(policy.freshLimit(
            limit,
            capturedAt: capture,
            now: try FixtureSupport.date("2026-08-12T01:15:01Z")
        ))
    }

    func testRejectsCaptureMateriallyAheadOfClock() throws {
        let capture = try FixtureSupport.date("2026-08-12T01:10:01Z")
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 20, resetsAt: nil),
            weekly: nil,
            source: .statusLine,
            capturedAt: capture
        )

        XCTAssertNil(policy.freshClaudeSnapshot(
            from: snapshot,
            now: try FixtureSupport.date("2026-08-12T01:05:00Z")
        ))
    }
}
