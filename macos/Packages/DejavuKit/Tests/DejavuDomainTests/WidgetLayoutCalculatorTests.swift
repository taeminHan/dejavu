import XCTest
@testable import DejavuDomain

final class WidgetLayoutCalculatorTests: XCTestCase {
    func testAllEightyFourCoreCombinationsProduceValidGeometry() {
        var combinations = 0

        for serviceState in WidgetServiceState.allCases {
            for density in WidgetDensity.allCases {
                for layout in WidgetLayout.allCases {
                    for showProgress in [false, true] {
                        let request = WidgetLayoutRequest(
                            density: density,
                            requestedLayout: layout,
                            serviceState: serviceState,
                            showProgress: showProgress
                        )
                        let metrics = WidgetLayoutCalculator.calculate(request)
                        let providerCount = serviceState.visibility.providerCount

                        XCTAssertGreaterThan(metrics.panelWidth, 0)
                        XCTAssertGreaterThan(metrics.panelHeight, 0)
                        XCTAssertEqual(metrics.providerOrder.count, providerCount)
                        XCTAssertEqual(metrics.smallRingDiameter, 30)
                        XCTAssertEqual(
                            metrics.effectiveLayout,
                            layout == .twoRows && providerCount == 2 ? .twoRows : .singleRow
                        )
                        XCTAssertEqual(metrics.providerGap == 0, providerCount < 2)
                        combinations += 1
                    }
                }
            }
        }

        XCTAssertEqual(combinations, 84)
    }

    func testZeroAndOneProviderTwoRowsExactlyMatchSingleRow() {
        let states: [WidgetServiceState] = [
            .autoNone, .forcedClaude, .forcedCodex, .autoClaude, .autoCodex
        ]
        var comparisons = 0

        for state in states {
            for density in WidgetDensity.allCases {
                for showProgress in [false, true] {
                    let single = WidgetLayoutCalculator.calculate(
                        WidgetLayoutRequest(
                            density: density,
                            requestedLayout: .singleRow,
                            serviceState: state,
                            showProgress: showProgress
                        )
                    )
                    let twoRows = WidgetLayoutCalculator.calculate(
                        WidgetLayoutRequest(
                            density: density,
                            requestedLayout: .twoRows,
                            serviceState: state,
                            showProgress: showProgress
                        )
                    )
                    XCTAssertEqual(twoRows, single)
                    comparisons += 1
                }
            }
        }

        XCTAssertEqual(comparisons, 30)
    }

    func testTwoProviderTwoRowsOrderCodexAboveClaude() {
        var states = 0
        for serviceState in [WidgetServiceState.forcedBoth, .autoBoth] {
            for density in WidgetDensity.allCases {
                for showProgress in [false, true] {
                    let metrics = WidgetLayoutCalculator.calculate(
                        WidgetLayoutRequest(
                            density: density,
                            requestedLayout: .twoRows,
                            serviceState: serviceState,
                            showProgress: showProgress
                        )
                    )
                    XCTAssertEqual(metrics.providerOrder, [.codex, .claude])
                    XCTAssertGreaterThan(metrics.providerGap, 0)
                    states += 1
                }
            }
        }
        XCTAssertEqual(states, 12)
    }

    func testAutomaticStatesMatchForcedGeometry() {
        let pairs: [(WidgetServiceState, WidgetServiceState)] = [
            (.autoClaude, .forcedClaude),
            (.autoCodex, .forcedCodex),
            (.autoBoth, .forcedBoth)
        ]
        var comparisons = 0

        for (automatic, forced) in pairs {
            for density in WidgetDensity.allCases {
                for layout in WidgetLayout.allCases {
                    for showProgress in [false, true] {
                        let automaticMetrics = WidgetLayoutCalculator.calculate(
                            WidgetLayoutRequest(
                                density: density,
                                requestedLayout: layout,
                                serviceState: automatic,
                                showProgress: showProgress
                            )
                        )
                        let forcedMetrics = WidgetLayoutCalculator.calculate(
                            WidgetLayoutRequest(
                                density: density,
                                requestedLayout: layout,
                                serviceState: forced,
                                showProgress: showProgress
                            )
                        )
                        XCTAssertEqual(automaticMetrics, forcedMetrics)
                        comparisons += 1
                    }
                }
            }
        }

        XCTAssertEqual(comparisons, 36)
    }

    func testHiddenProviderLeavesNoGapAndCodexOnlyHasNoLeadingGap() {
        for density in WidgetDensity.allCases {
            let codexOnly = WidgetLayoutCalculator.calculate(
                WidgetLayoutRequest(
                    density: density,
                    requestedLayout: .singleRow,
                    serviceState: .forcedCodex,
                    showProgress: true
                )
            )
            XCTAssertEqual(codexOnly.providerGap, 0)
            XCTAssertEqual(codexOnly.providerOrder, [.codex])
        }
    }

    func testProgressFootprintIsOwnedByCalculator() {
        for density in [WidgetDensity.compact, .comfortable] {
            let hidden = WidgetLayoutCalculator.calculate(
                WidgetLayoutRequest(
                    density: density,
                    requestedLayout: .singleRow,
                    serviceState: .forcedClaude,
                    showProgress: false
                )
            )
            let shown = WidgetLayoutCalculator.calculate(
                WidgetLayoutRequest(
                    density: density,
                    requestedLayout: .singleRow,
                    serviceState: .forcedClaude,
                    showProgress: true
                )
            )
            XCTAssertEqual(hidden.progressFootprint, 0)
            XCTAssertGreaterThan(shown.progressFootprint, 0)
            XCTAssertEqual(shown.panelHeight - hidden.panelHeight, shown.progressFootprint)
            XCTAssertEqual(shown.panelWidth, hidden.panelWidth)
        }
    }

    func testAccessibilityScaleIsBoundedAndExpandsContent() {
        let baseline = WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: .compact,
                requestedLayout: .singleRow,
                serviceState: .forcedBoth,
                showProgress: true,
                accessibilityTextScale: 1
            )
        )
        let enlarged = WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: .compact,
                requestedLayout: .singleRow,
                serviceState: .forcedBoth,
                showProgress: true,
                accessibilityTextScale: 1.8
            )
        )
        let capped = WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: .compact,
                requestedLayout: .singleRow,
                serviceState: .forcedBoth,
                showProgress: true,
                accessibilityTextScale: 50
            )
        )

        XCTAssertGreaterThan(enlarged.panelWidth, baseline.panelWidth)
        XCTAssertGreaterThan(enlarged.panelHeight, baseline.panelHeight)
        XCTAssertLessThanOrEqual(enlarged.panelWidth, capped.panelWidth)
    }

    func testFableAddsAFullThirdClaudeMetricSlotWithoutChangingCodexWidth() {
        let standard = WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: .compact,
                requestedLayout: .singleRow,
                serviceState: .forcedBoth,
                showProgress: true
            )
        )
        let withFable = WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: .compact,
                requestedLayout: .singleRow,
                showClaude: true,
                showCodex: true,
                showProgress: true,
                claudeMetricSlots: 3
            )
        )

        XCTAssertEqual(
            withFable.claudeContentWidth - standard.claudeContentWidth,
            standard.metricCellWidth + standard.metricGap
        )
        XCTAssertEqual(withFable.codexContentWidth, standard.codexContentWidth)
        XCTAssertEqual(
            withFable.panelWidth - standard.panelWidth,
            standard.metricCellWidth + standard.metricGap
        )
    }

    func testTwoRowFableLayoutUsesWiderClaudeRow() {
        let metrics = WidgetLayoutCalculator.calculate(
            WidgetLayoutRequest(
                density: .compact,
                requestedLayout: .twoRows,
                showClaude: true,
                showCodex: true,
                showProgress: true,
                claudeMetricSlots: 3
            )
        )

        XCTAssertEqual(metrics.effectiveLayout, .twoRows)
        XCTAssertGreaterThan(metrics.claudeContentWidth, metrics.codexContentWidth)
        XCTAssertEqual(
            metrics.panelWidth,
            metrics.claudeContentWidth + metrics.contentPadding * 2
        )
    }
}
