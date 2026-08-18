import XCTest
@testable import DejavuDomain

final class MenuBarSummaryFormatterTests: XCTestCase {
    func testStructuredSummaryKeepsBrandNamesOutOfCompactValues() {
        let summary = MenuBarSummaryFormatter.summary(
            claudeFiveHour: UsageLimit(percent: 38),
            claudeWeekly: UsageLimit(percent: 39),
            claudeFable: UsageLimit(percent: 12),
            isClaudeVisible: true,
            codexWeekly: UsageLimit(percent: 47),
            isCodexVisible: true,
            claudeMetric: .fiveHour,
            codexMetric: .weekly
        )

        XCTAssertEqual(summary.claudeValue, "5h 38%")
        XCTAssertEqual(summary.codexValue, "47%")
        XCTAssertEqual(summary.accessibilityTitle, "Claude 5h 38%, Codex 47%")
    }

    func testDefaultSummaryExample() {
        XCTAssertEqual(
            title(
                claudeFiveHour: 38,
                claudeWeekly: 39,
                codexWeekly: 47
            ),
            "5h 38% · Codex 47%"
        )
    }

    func testClaudeCanSelectFiveHourWeeklyFableOrHiddenAndCodexCanSelectWeeklyOrHidden() {
        XCTAssertEqual(
            title(claudeFiveHour: 11, claudeWeekly: 22, codexWeekly: 44),
            "5h 11% · Codex 44%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 11,
                claudeWeekly: 22,
                claudeFable: 33,
                codexWeekly: 44,
                claudeMetric: .fable
            ),
            "Fable 33% · Codex 44%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 11,
                claudeWeekly: 22,
                codexWeekly: 44,
                claudeMetric: .weekly,
                codexMetric: .fiveHour
            ),
            "7d 22% · Codex 44%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 11,
                claudeWeekly: 22,
                codexWeekly: 44,
                claudeMetric: .hidden
            ),
            "Codex 44%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 11,
                claudeWeekly: 22,
                codexWeekly: 44,
                codexMetric: .hidden
            ),
            "5h 11%"
        )
    }

    func testVisibleProviderWithMissingSelectedWindowUsesPlaceholder() {
        XCTAssertEqual(
            MenuBarSummaryFormatter.title(
                claudeFiveHour: UsageLimit(percent: 88),
                claudeWeekly: nil,
                isClaudeVisible: true,
                codexWeekly: UsageLimit(percent: 55),
                isCodexVisible: true,
                claudeMetric: .weekly,
                codexMetric: .fiveHour
            ),
            "7d --% · Codex 55%"
        )
        XCTAssertEqual(
            MenuBarSummaryFormatter.title(
                claudeFiveHour: UsageLimit(percent: 88),
                claudeWeekly: UsageLimit(percent: 44),
                claudeFable: nil,
                isClaudeVisible: true,
                codexWeekly: nil,
                isCodexVisible: false,
                claudeMetric: .fable,
                codexMetric: .hidden
            ),
            "Fable --%"
        )
    }

    func testOnlyVisibleProviderLeavesNoOtherProviderSpace() {
        XCTAssertEqual(
            title(
                claudeFiveHour: 10,
                claudeWeekly: 20,
                codexWeekly: 40,
                isClaudeVisible: true,
                isCodexVisible: false
            ),
            "5h 10%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 10,
                claudeWeekly: 20,
                codexWeekly: 40,
                isClaudeVisible: false,
                isCodexVisible: true
            ),
            "Codex 40%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 10,
                claudeWeekly: 20,
                codexWeekly: 40,
                isClaudeVisible: true,
                isCodexVisible: false,
                claudeMetric: .hidden
            ),
            ""
        )
    }

    func testNoAvailableProvidersRetainsOnlyNonHiddenConfiguredPlaceholders() {
        XCTAssertEqual(
            title(
                claudeFiveHour: 10,
                claudeWeekly: 20,
                codexWeekly: 40,
                isClaudeVisible: false,
                isCodexVisible: false
            ),
            "5h --% · Codex --%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 10,
                claudeWeekly: 20,
                codexWeekly: 40,
                isClaudeVisible: false,
                isCodexVisible: false,
                claudeMetric: .hidden
            ),
            "Codex --%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 10,
                claudeWeekly: 20,
                codexWeekly: 40,
                isClaudeVisible: false,
                isCodexVisible: false,
                claudeMetric: .hidden,
                codexMetric: .hidden
            ),
            ""
        )
    }

    func testPercentUsesDisplayClampAndRoundedIntegerText() {
        XCTAssertEqual(
            title(
                claudeFiveHour: -4,
                claudeWeekly: 20,
                codexWeekly: 100.7
            ),
            "5h 0% · Codex 100%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: 38.5,
                claudeWeekly: 20,
                codexWeekly: 47.49
            ),
            "5h 39% · Codex 47%"
        )
        XCTAssertEqual(
            title(
                claudeFiveHour: .nan,
                claudeWeekly: 20,
                codexWeekly: .infinity
            ),
            "5h 0% · Codex 100%"
        )
    }

    func testAllVisibilityAndMetricCombinationsHaveCanonicalComposition() {
        var combinations = 0

        for isClaudeVisible in [false, true] {
            for isCodexVisible in [false, true] {
                for claudeMetric in MenuBarMetric.allCases {
                    for codexMetric in MenuBarMetric.allCases {
                        let result = title(
                            claudeFiveHour: 11,
                            claudeWeekly: 22,
                            codexWeekly: 44,
                            isClaudeVisible: isClaudeVisible,
                            isCodexVisible: isCodexVisible,
                            claudeMetric: claudeMetric,
                            codexMetric: codexMetric
                        )
                        let segments = result.isEmpty ? [] : result.components(separatedBy: " · ")
                        let hasVisibleProvider = isClaudeVisible || isCodexVisible
                        let expectedClaude = claudeMetric != .hidden
                            && (hasVisibleProvider ? isClaudeVisible : true)
                        let expectedCodex = codexMetric != .hidden
                            && (hasVisibleProvider ? isCodexVisible : true)

                        XCTAssertEqual(segments.count, (expectedClaude ? 1 : 0) + (expectedCodex ? 1 : 0))
                        XCTAssertEqual(segments.filter { $0.hasPrefix("Codex ") }.count, expectedCodex ? 1 : 0)
                        XCTAssertFalse(result.hasPrefix(" · "))
                        XCTAssertFalse(result.hasSuffix(" · "))
                        XCTAssertFalse(result.contains(" ·  · "))
                        combinations += 1
                    }
                }
            }
        }

        XCTAssertEqual(combinations, 64)
    }

    func testMultipleClaudeMetricsAndCodexComposeInCanonicalOrder() {
        let summary = MenuBarSummaryFormatter.summary(
            claudeFiveHour: UsageLimit(percent: 12),
            claudeWeekly: UsageLimit(percent: 73),
            claudeFable: UsageLimit(percent: 94),
            isClaudeVisible: true,
            codexWeekly: UsageLimit(percent: 47),
            isCodexVisible: true,
            claudeMetrics: [.fable, .fiveHour, .weekly],
            showsCodex: true
        )

        XCTAssertEqual(summary.items.map(\.value), ["5h 12%", "7d 73%", "Fable 94%", "47%"])
        XCTAssertEqual(summary.items.map(\.displayPercent), [12, 73, 94, 47])
        XCTAssertEqual(
            summary.accessibilityTitle,
            "Claude 5h 12%, Claude 7d 73%, Claude Fable 94%, Codex 47%"
        )
    }

    func testEveryMetricCanBeHiddenIndependently() {
        let summary = MenuBarSummaryFormatter.summary(
            claudeFiveHour: UsageLimit(percent: 12),
            claudeWeekly: UsageLimit(percent: 73),
            claudeFable: UsageLimit(percent: 94),
            isClaudeVisible: true,
            codexWeekly: UsageLimit(percent: 47),
            isCodexVisible: true,
            claudeMetrics: [.weekly],
            showsCodex: false
        )

        XCTAssertEqual(summary.items.map(\.value), ["7d 73%"])
    }

    private func title(
        claudeFiveHour: Double?,
        claudeWeekly: Double?,
        claudeFable: Double? = nil,
        codexWeekly: Double?,
        isClaudeVisible: Bool = true,
        isCodexVisible: Bool = true,
        claudeMetric: MenuBarMetric = .fiveHour,
        codexMetric: MenuBarMetric = .weekly
    ) -> String {
        MenuBarSummaryFormatter.title(
            claudeFiveHour: claudeFiveHour.map { UsageLimit(percent: $0) },
            claudeWeekly: claudeWeekly.map { UsageLimit(percent: $0) },
            claudeFable: claudeFable.map { UsageLimit(percent: $0) },
            isClaudeVisible: isClaudeVisible,
            codexWeekly: codexWeekly.map { UsageLimit(percent: $0) },
            isCodexVisible: isCodexVisible,
            claudeMetric: claudeMetric,
            codexMetric: codexMetric
        )
    }
}
