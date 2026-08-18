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
}
