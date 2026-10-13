import Foundation
import XCTest
import DejavuDomain
@testable import DejavuProviders

final class CodexRateLimitsParserTests: XCTestCase {
    private let parser = CodexRateLimitsParser()

    func testExactCodexBucketWinsOverLegacyAndOtherBuckets() throws {
        let snapshot = try parser.parseResponse(
            FixtureSupport.data(named: "codex-exact-bucket.json")
        )

        XCTAssertEqual(snapshot.weekly?.percent, 40)
        XCTAssertEqual(snapshot.planType, "plus")
        XCTAssertEqual(snapshot.resetCredits, 3)
        XCTAssertEqual(snapshot.resetCreditsExpireAt, Date(timeIntervalSince1970: 1_786_900_000))
    }

    func testFallsBackToLegacyWhenMultiBucketViewIsAbsent() throws {
        let snapshot = try parser.parseResponse(
            FixtureSupport.data(named: "codex-legacy-bucket.json")
        )

        XCTAssertEqual(snapshot.weekly?.percent, 22)
        XCTAssertEqual(snapshot.planType, "team")
        XCTAssertEqual(snapshot.resetCredits, 0)
        XCTAssertNil(snapshot.resetCreditsExpireAt)
    }

    func testNeverMixesCodexOtherOrLegacyIntoPresentMultiBucketView() throws {
        let snapshot = try parser.parseResponse(
            FixtureSupport.data(named: "codex-other-only.json")
        )

        XCTAssertNil(snapshot.weekly)
        XCTAssertNil(snapshot.planType)
    }

    func testAuthoritativeResetCountDoesNotDependOnDetailRows() throws {
        let snapshot = try parser.parseResponse(
            FixtureSupport.data(named: "codex-reset-count-only.json")
        )

        XCTAssertEqual(snapshot.resetCredits, 5)
        XCTAssertNil(snapshot.resetCreditsExpireAt)
    }

    func testDetailRowsNeverReplaceMissingAuthoritativeCount() throws {
        let snapshot = try parser.parseResponse(
            FixtureSupport.data(named: "codex-reset-details-no-count.json")
        )

        XCTAssertNil(snapshot.resetCredits)
        XCTAssertEqual(snapshot.resetCreditsExpireAt, Date(timeIntervalSince1970: 1_786_900_000))
    }

    func testShortWindowIsNeverExposedAsCodexUsage() throws {
        let snapshot = try parser.parseResponse(
            FixtureSupport.data(named: "codex-missing-windows.json")
        )
        XCTAssertNil(snapshot.weekly)
    }

    func testMalformedOptionalPrimaryDoesNotDiscardWeeklyOrCredits() throws {
        for primary in [#"{"usedPercent":null,"windowDurationMins":300}"#, #"{"usedPercent":12}"#, #"{"usedPercent":"changed","windowDurationMins":300}"#] {
            let json = #"{"id":3,"result":{"rateLimits":{"primary":PRIMARY,"secondary":{"usedPercent":42,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":2}}}"#.replacingOccurrences(of: "PRIMARY", with: primary)
            let snapshot = try parser.parseResponse(Data(json.utf8))
            XCTAssertEqual(snapshot.weekly?.percent, 42)
            XCTAssertEqual(snapshot.resetCredits, 2)
        }
    }

    func testNullUnrelatedBucketDoesNotDiscardExactCodexBucket() throws {
        let data = Data(#"{"result":{"rateLimitsByLimitId":{"other":null,"codex":{"secondary":{"usedPercent":37,"windowDurationMins":10080}}}}}"#.utf8)
        XCTAssertEqual(try parser.parseResponse(data).weekly?.percent, 37)
    }

    func testRejectsResponseErrorAndMissingResult() {
        XCTAssertThrowsError(
            try parser.parseResponse(Data(#"{"id":6,"error":{}}"#.utf8))
        ) { error in
            XCTAssertEqual(error as? CodexRateLimitsParserError, .responseError)
        }
        XCTAssertThrowsError(
            try parser.parseResponse(Data(#"{"id":6}"#.utf8))
        ) { error in
            XCTAssertEqual(error as? CodexRateLimitsParserError, .missingResult)
        }
    }
}
