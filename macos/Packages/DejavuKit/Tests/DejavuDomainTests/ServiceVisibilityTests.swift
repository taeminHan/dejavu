import XCTest
@testable import DejavuDomain

final class ServiceVisibilityTests: XCTestCase {
    func testForcedModesIgnoreDetection() {
        XCTAssertEqual(
            ServiceVisibilityResolver.resolve(
                mode: .claudeAndCodex,
                claudeAvailable: false,
                codexAvailable: false
            ),
            ServiceVisibility(showClaude: true, showCodex: true)
        )
        XCTAssertEqual(
            ServiceVisibilityResolver.resolve(
                mode: .claudeOnly,
                claudeAvailable: false,
                codexAvailable: true
            ),
            ServiceVisibility(showClaude: true, showCodex: false)
        )
        XCTAssertEqual(
            ServiceVisibilityResolver.resolve(
                mode: .codexOnly,
                claudeAvailable: true,
                codexAvailable: false
            ),
            ServiceVisibility(showClaude: false, showCodex: true)
        )
    }

    func testAutomaticDetectionCoversAllFourAvailabilityStates() {
        for claude in [false, true] {
            for codex in [false, true] {
                XCTAssertEqual(
                    ServiceVisibilityResolver.resolve(
                        mode: .autoDetect,
                        claudeAvailable: claude,
                        codexAvailable: codex
                    ),
                    ServiceVisibility(showClaude: claude, showCodex: codex)
                )
            }
        }
    }

    func testAutomaticDetectionKeepsProviderWithPreviousSnapshotDuringOfflineState() {
        let snapshot = ClaudeUsageSnapshot(
            fiveHour: UsageLimit(percent: 25),
            weekly: nil,
            capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        let state = ApplicationState(
            claudeStatus: .offline,
            claudeSnapshot: snapshot,
            codexStatus: .unavailable
        )

        XCTAssertEqual(
            ServiceVisibilityResolver.resolve(mode: .autoDetect, state: state),
            ServiceVisibility(showClaude: true, showCodex: false)
        )
    }

    func testSevenProbeStatesResolveToExpectedVisibility() {
        XCTAssertEqual(WidgetServiceState.allCases.count, 7)
        XCTAssertEqual(WidgetServiceState.forcedBoth.visibility.providerCount, 2)
        XCTAssertEqual(WidgetServiceState.forcedClaude.visibility.providerCount, 1)
        XCTAssertEqual(WidgetServiceState.forcedCodex.visibility.providerCount, 1)
        XCTAssertEqual(WidgetServiceState.autoNone.visibility.providerCount, 0)
        XCTAssertEqual(WidgetServiceState.autoClaude.visibility, WidgetServiceState.forcedClaude.visibility)
        XCTAssertEqual(WidgetServiceState.autoCodex.visibility, WidgetServiceState.forcedCodex.visibility)
        XCTAssertEqual(WidgetServiceState.autoBoth.visibility, WidgetServiceState.forcedBoth.visibility)
    }
}
