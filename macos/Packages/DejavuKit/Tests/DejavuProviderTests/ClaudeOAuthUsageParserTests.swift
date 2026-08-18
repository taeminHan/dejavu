import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class ClaudeOAuthUsageParserTests: XCTestCase {
    private let parser = ClaudeOAuthUsageParser()

    func testParsesSessionWeeklyAndScopedFable() throws {
        let capturedAt = try FixtureSupport.date("2026-08-13T01:00:00Z")

        let snapshot = try parser.parse(
            FixtureSupport.data(named: "claude-oauth-usage-fable.json"),
            capturedAt: capturedAt
        )

        XCTAssertEqual(snapshot.fiveHour?.percent, 18.5)
        XCTAssertEqual(snapshot.weekly?.percent, 39)
        XCTAssertEqual(snapshot.fable?.percent, 12.25)
        XCTAssertEqual(snapshot.fable?.resetsAt, try FixtureSupport.date("2026-08-20T01:00:00Z"))
        XCTAssertEqual(snapshot.source, .oauthUsage)
        XCTAssertEqual(snapshot.capturedAt, capturedAt)
    }

    func testIgnoresOtherModelScopedLimits() throws {
        let data = Data(#"""
        {
          "limits": [
            {
              "kind": "weekly_scoped",
              "percent": 77,
              "resets_at": "2026-08-20T01:00:00Z",
              "scope": { "model": { "display_name": "Opus" } }
            },
            {
              "kind": "weekly_scoped",
              "percent": 66,
              "resets_at": "2026-08-20T01:00:00Z",
              "scope": { "model": { "display_name": "Sonnet" } }
            }
          ]
        }
        """#.utf8)

        let snapshot = try parser.parse(data, capturedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertNil(snapshot.fable)
    }

    func testUsesOnlyExplicitLegacyFableField() throws {
        let data = Data(#"""
        {
          "seven_day_fable": {
            "utilization": 31,
            "resets_at": "2026-08-20T01:00:00Z"
          },
          "seven_day_opus": {
            "utilization": 99,
            "resets_at": "2026-08-20T01:00:00Z"
          }
        }
        """#.utf8)

        let snapshot = try parser.parse(data, capturedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(snapshot.fable?.percent, 31)
    }

    func testMissingFableRemainsUnavailable() throws {
        let snapshot = try parser.parse(
            Data(#"{"limits":[]}"#.utf8),
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertNil(snapshot.fiveHour)
        XCTAssertNil(snapshot.weekly)
        XCTAssertNil(snapshot.fable)
    }
}
