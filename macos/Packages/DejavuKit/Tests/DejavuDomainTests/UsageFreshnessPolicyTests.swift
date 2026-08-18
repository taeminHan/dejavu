import XCTest
@testable import DejavuDomain

final class UsageFreshnessPolicyTests: XCTestCase {
    func testExpiresWindowsIndependentlyAtReset() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 25, resetsAt: now.addingTimeInterval(-1)),
            weekly: UsageLimit(percent: 50, resetsAt: now.addingTimeInterval(60)),
            capturedAt: now.addingTimeInterval(-30)
        )

        let fresh = UsageFreshnessPolicy().freshClaudeSnapshot(from: snapshot, now: now)

        XCTAssertNil(fresh?.fiveHour)
        XCTAssertEqual(fresh?.weekly?.displayPercent, 50)
    }

    func testResetlessWindowUsesConservativeTTL() {
        let now = Date(timeIntervalSince1970: 10_000)
        let policy = UsageFreshnessPolicy(maximumAgeWithoutReset: 300)
        let fresh = UsageLimit(percent: 10)

        XCTAssertNotNil(policy.freshLimit(fresh, capturedAt: now.addingTimeInterval(-299), now: now))
        XCTAssertNil(policy.freshLimit(fresh, capturedAt: now.addingTimeInterval(-301), now: now))
    }

    func testRejectsImplausibleFutureCapture() {
        let now = Date(timeIntervalSince1970: 10_000)
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 25, resetsAt: now.addingTimeInterval(600)),
            weekly: nil,
            capturedAt: now.addingTimeInterval(61)
        )

        XCTAssertNil(UsageFreshnessPolicy().freshClaudeSnapshot(from: snapshot, now: now))
    }
}
