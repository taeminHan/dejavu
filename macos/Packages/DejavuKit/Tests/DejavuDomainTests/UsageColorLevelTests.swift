import XCTest
@testable import DejavuDomain

final class UsageColorLevelTests: XCTestCase {
    func testWindowsCompatibleThresholdBoundaries() {
        XCTAssertEqual(UsageColorLevel.level(for: nil), .normal)
        XCTAssertEqual(UsageColorLevel.level(for: 69.999), .normal)
        XCTAssertEqual(UsageColorLevel.level(for: 70), .warning)
        XCTAssertEqual(UsageColorLevel.level(for: 89.999), .warning)
        XCTAssertEqual(UsageColorLevel.level(for: 90), .danger)
        XCTAssertEqual(UsageColorLevel.level(for: 100), .danger)
    }
}
