import Foundation
import XCTest
@testable import DejavuDomain

final class UpdatePolicyTests: XCTestCase {
    func testNextCheckUsesNextLocalClockHourInsteadOfFixedInterval() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 20, minute: 37, second: 41
        )))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 21
        )))

        XCTAssertEqual(HourlyUpdateSchedule.nextCheckAt(after: now, calendar: calendar), expected)
    }

    func testNextCheckCrossesDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Seoul"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13, hour: 23, minute: 59
        )))
        let expected = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 14, hour: 0
        )))

        XCTAssertEqual(HourlyUpdateSchedule.nextCheckAt(after: now, calendar: calendar), expected)
    }

    func testAutomaticNotificationIsOncePerNonemptyVersion() {
        XCTAssertFalse(AutomaticUpdatePolicy.shouldNotify(
            availableVersion: nil,
            lastNotifiedVersion: nil
        ))
        XCTAssertFalse(AutomaticUpdatePolicy.shouldNotify(
            availableVersion: "  ",
            lastNotifiedVersion: nil
        ))
        XCTAssertFalse(AutomaticUpdatePolicy.shouldNotify(
            availableVersion: " 1.2.3 ",
            lastNotifiedVersion: "1.2.3"
        ))
        XCTAssertFalse(AutomaticUpdatePolicy.shouldNotify(
            availableVersion: "1.2.3-BETA",
            lastNotifiedVersion: "1.2.3-beta"
        ))
        XCTAssertTrue(AutomaticUpdatePolicy.shouldNotify(
            availableVersion: "1.2.4",
            lastNotifiedVersion: "1.2.3"
        ))
    }

    func testManualFailurePreservesPreviouslyDiscoveredRelease() {
        var state = UpdateCheckState()
        state.foundUpdate(version: "0.9.6")
        state.beginCheck(manual: true)
        XCTAssertEqual(state.presentation, .checking)
        XCTAssertEqual(state.availableVersion, "0.9.6")

        state.finish(outcome: .failed, manual: true)
        XCTAssertEqual(state.presentation, .available(version: "0.9.6"))
        XCTAssertEqual(state.availableVersion, "0.9.6")
    }

    func testAutomaticFailureSilentlyPreservesDiscoveredRelease() {
        var state = UpdateCheckState()
        state.foundUpdate(version: "0.9.6")
        state.beginCheck(manual: false)
        XCTAssertEqual(state.presentation, .available(version: "0.9.6"))
        state.finish(outcome: .failed, manual: false)
        XCTAssertEqual(state.presentation, .available(version: "0.9.6"))
    }

    func testDefinitiveNoUpdateClearsReleaseForEitherCheckKind() {
        for manual in [false, true] {
            var state = UpdateCheckState()
            state.foundUpdate(version: "0.9.6")
            state.beginCheck(manual: manual)
            state.finish(outcome: .noUpdate, manual: manual)
            XCTAssertNil(state.availableVersion)
            XCTAssertEqual(state.presentation, manual ? .current : .ready)
        }
    }

    func testFailureWithoutDiscoveredReleaseOnlyShowsForManualCheck() {
        for manual in [false, true] {
            var state = UpdateCheckState()
            state.beginCheck(manual: manual)
            state.finish(outcome: .failed, manual: manual)
            XCTAssertEqual(state.presentation, manual ? .failed : .ready)
        }
    }

    func testSuccessfulCycleRetainsFoundReleaseAndRejectsEmptyVersions() {
        var state = UpdateCheckState()
        state.beginCheck(manual: true)
        state.foundUpdate(version: " 0.9.6 ")
        state.foundUpdate(version: " \n ")
        state.finish(outcome: .completed, manual: true)
        XCTAssertEqual(state.availableVersion, "0.9.6")
        XCTAssertEqual(state.presentation, .available(version: "0.9.6"))
    }
}
