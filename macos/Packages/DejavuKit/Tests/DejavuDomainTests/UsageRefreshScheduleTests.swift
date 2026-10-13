import XCTest
@testable import DejavuDomain

final class UsageRefreshScheduleTests: XCTestCase {
    func testBoundedEarlyRetriesThenNormalIntervalAndRecovery() {
        var schedule = UsageRefreshSchedule()
        let now = ContinuousClock.now
        let failed = ApplicationState(claudeStatus: .offline, codexStatus: .ready)
        for seconds in [10, 30, 120, 120] {
            schedule.completed(state: failed, interval: 120, now: now)
            XCTAssertEqual(schedule.deadline, now.advanced(by: .seconds(seconds)))
        }
        schedule.completed(state: .init(claudeStatus: .ready, codexStatus: .ready), interval: 120, now: now)
        XCTAssertEqual(schedule.transientFailures, 0)
        schedule.completed(state: failed, interval: 120, now: now)
        XCTAssertEqual(schedule.deadline, now.advanced(by: .seconds(10)))
    }

    func testSettingsCannotPostponePendingNudge() {
        var schedule = UsageRefreshSchedule()
        let now = ContinuousClock.now
        schedule.bringForward(after: 5, now: now)
        schedule.bringForward(after: 300, now: now)
        XCTAssertEqual(schedule.deadline, now.advanced(by: .seconds(5)))
        schedule.bringForward(after: 2, now: now)
        XCTAssertEqual(schedule.deadline, now.advanced(by: .seconds(2)))
    }

    func testRateLimitDoesNotTriggerTransientRetryAndCapsNextCheck() {
        var schedule = UsageRefreshSchedule()
        let now = ContinuousClock.now
        let wallNow = Date(timeIntervalSince1970: 1000)
        let limited = ApplicationState(claudeStatus: .rateLimited, codexStatus: .ready,
                                       retryAt: wallNow.addingTimeInterval(90))
        schedule.completed(state: limited, interval: 300, wallNow: wallNow, now: now)
        XCTAssertEqual(schedule.deadline, now.advanced(by: .seconds(90.5)))
        XCTAssertEqual(schedule.transientFailures, 0)
    }

    func testTokenRefreshPendingDoesNotSpendEarlyRetries() {
        var schedule = UsageRefreshSchedule()
        let now = ContinuousClock.now
        schedule.completed(state: .init(claudeStatus: .error, codexStatus: .ready,
                                        claudeIssue: .tokenRefreshPending), interval: 120, now: now)
        XCTAssertEqual(schedule.deadline, now.advanced(by: .seconds(120)))
        XCTAssertEqual(schedule.transientFailures, 0)
    }
}
