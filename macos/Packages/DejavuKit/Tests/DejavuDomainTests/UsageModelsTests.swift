import XCTest
@testable import DejavuDomain

final class UsageModelsTests: XCTestCase {
    func testDisplayPercentClampsOnceForTextAndGeometry() {
        let belowRange = UsageLimit(percent: -12)
        let inRange = UsageLimit(percent: 41.25)
        let aboveRange = UsageLimit(percent: 143)

        XCTAssertEqual(belowRange.displayPercent, 0)
        XCTAssertEqual(belowRange.progressFraction, 0)
        XCTAssertEqual(inRange.displayPercent, 41.25)
        XCTAssertEqual(inRange.progressFraction, 0.4125)
        XCTAssertEqual(aboveRange.displayPercent, 100)
        XCTAssertEqual(aboveRange.progressFraction, 1)
        XCTAssertEqual(UsageLimit(percent: .nan).displayPercent, 0)
        XCTAssertEqual(UsageLimit(percent: .infinity).displayPercent, 100)
    }

    func testMissingLimitStaysMissingInsteadOfBecomingZero() {
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: nil,
            weekly: UsageLimit(percent: 0),
            fable: nil,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.weekly?.displayPercent, 0)
        XCTAssertNil(snapshot.fable)
    }

    func testClaudeSnapshotDecodesOlderPayloadWithoutFable() throws {
        let data = Data(#"""
        {
          "fiveHour": null,
          "weekly": { "percent": 42, "resetsAt": null },
          "source": "statusLine",
          "capturedAt": 1000
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let snapshot = try decoder.decode(ClaudeUsageSnapshot.self, from: data)

        XCTAssertEqual(snapshot.weekly?.percent, 42)
        XCTAssertNil(snapshot.fable)
    }

    func testUsageStatusesUseStableStringEncoding() throws {
        let data = try JSONEncoder().encode(UsageStatus.loginRequired)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"loginRequired\"")
        XCTAssertEqual(try JSONDecoder().decode(UsageStatus.self, from: data), .loginRequired)
    }

    func testCombinedStatusFollowsProviderPrecedence() {
        XCTAssertEqual(UsageStatus.combined(claude: .offline, codex: .ready), .ready)
        XCTAssertEqual(UsageStatus.combined(claude: .loading, codex: .offline), .loading)
        XCTAssertEqual(UsageStatus.combined(claude: .rateLimited, codex: .offline), .rateLimited)
        XCTAssertEqual(UsageStatus.combined(claude: .offline, codex: .error), .offline)
        XCTAssertEqual(UsageStatus.combined(claude: .loginRequired, codex: .loginRequired), .loginRequired)
        XCTAssertEqual(UsageStatus.combined(claude: .unavailable, codex: .unavailable), .unavailable)
        XCTAssertEqual(UsageStatus.combined(claude: .loginRequired, codex: .unavailable), .error)
    }

    func testLoadingStatePreservesLastValidSnapshots() {
        let capturedAt = Date(timeIntervalSince1970: 2_000)
        let claude = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 10),
            weekly: nil,
            capturedAt: capturedAt
        )
        let codex = CodexUsageSnapshot(
            weekly: UsageLimit(percent: 20),
            resetCredits: 3,
            resetCreditsExpireAt: nil,
            planType: "plus"
        )
        let ready = ApplicationState(
            claudeStatus: .ready,
            claudeSnapshot: claude,
            codexStatus: .ready,
            codexSnapshot: codex,
            updatedAt: capturedAt
        )

        let loading = ready.loading()

        XCTAssertEqual(loading.combinedStatus, .loading)
        XCTAssertEqual(loading.claudeStatus, .loading)
        XCTAssertEqual(loading.codexStatus, .loading)
        XCTAssertEqual(loading.claudeSnapshot, claude)
        XCTAssertEqual(loading.codexSnapshot, codex)
        XCTAssertEqual(loading.updatedAt, capturedAt)
    }

    func testCodexSnapshotDecodesLegacyPayloadWithoutExposingFiveHour() throws {
        let data = Data(#"""
        {
          "fiveHour": { "percent": 91, "resetsAt": null },
          "weekly": { "percent": 27, "resetsAt": null },
          "resetCredits": null,
          "resetCreditsExpireAt": null,
          "planType": "plus"
        }
        """#.utf8)

        let snapshot = try JSONDecoder().decode(CodexUsageSnapshot.self, from: data)
        let encoded = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(snapshot.weekly?.percent, 27)
        XCTAssertNil(object["fiveHour"])
    }
}
