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
