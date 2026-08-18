import Foundation

public struct MenuBarSummary: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public enum Provider: String, Sendable {
            case claude
            case codex
        }

        public let provider: Provider
        public let metric: MenuBarMetric
        public let value: String
        public let displayPercent: Double?

        public init(
            provider: Provider,
            metric: MenuBarMetric,
            value: String,
            displayPercent: Double?
        ) {
            self.provider = provider
            self.metric = metric
            self.value = value
            self.displayPercent = displayPercent
        }
    }

    public let items: [Item]

    public var claudeValue: String? {
        items.first { $0.provider == .claude }?.value
    }

    public var codexValue: String? {
        items.first { $0.provider == .codex }?.value
    }

    public init(claudeValue: String?, codexValue: String?) {
        items = [
            claudeValue.map {
                Item(provider: .claude, metric: .fiveHour, value: $0, displayPercent: nil)
            },
            codexValue.map {
                Item(provider: .codex, metric: .weekly, value: $0, displayPercent: nil)
            }
        ].compactMap { $0 }
    }

    public init(items: [Item]) {
        self.items = items
    }

    /// A text-only equivalent for accessibility and surfaces that cannot
    /// render provider artwork.
    public var accessibilityTitle: String {
        items.map { item in
            "\(item.provider == .claude ? "Claude" : "Codex") \(item.value)"
        }
        .joined(separator: ", ")
    }
}

/// Produces the compact, provider-aware menu bar title without UI dependencies.
public enum MenuBarSummaryFormatter {
    public static func title(
        claudeFiveHour: UsageLimit?,
        claudeWeekly: UsageLimit?,
        claudeFable: UsageLimit? = nil,
        isClaudeVisible: Bool,
        codexWeekly: UsageLimit?,
        isCodexVisible: Bool,
        claudeMetric: MenuBarMetric,
        codexMetric: MenuBarMetric
    ) -> String {
        let summary = summary(
            claudeFiveHour: claudeFiveHour,
            claudeWeekly: claudeWeekly,
            claudeFable: claudeFable,
            isClaudeVisible: isClaudeVisible,
            codexWeekly: codexWeekly,
            isCodexVisible: isCodexVisible,
            claudeMetric: claudeMetric,
            codexMetric: codexMetric
        )
        return [
            summary.claudeValue,
            summary.codexValue.map { "Codex \($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    public static func summary(
        claudeFiveHour: UsageLimit?,
        claudeWeekly: UsageLimit?,
        claudeFable: UsageLimit? = nil,
        isClaudeVisible: Bool,
        codexWeekly: UsageLimit?,
        isCodexVisible: Bool,
        claudeMetric: MenuBarMetric,
        codexMetric: MenuBarMetric
    ) -> MenuBarSummary {
        summary(
            claudeFiveHour: claudeFiveHour,
            claudeWeekly: claudeWeekly,
            claudeFable: claudeFable,
            isClaudeVisible: isClaudeVisible,
            codexWeekly: codexWeekly,
            isCodexVisible: isCodexVisible,
            claudeMetrics: claudeMetric == .hidden ? [] : [claudeMetric],
            showsCodex: codexMetric != .hidden
        )
    }

    public static func summary(
        claudeFiveHour: UsageLimit?,
        claudeWeekly: UsageLimit?,
        claudeFable: UsageLimit? = nil,
        isClaudeVisible: Bool,
        codexWeekly: UsageLimit?,
        isCodexVisible: Bool,
        claudeMetrics: [MenuBarMetric],
        showsCodex: Bool
    ) -> MenuBarSummary {
        let hasVisibleProvider = isClaudeVisible || isCodexVisible
        var items = [MenuBarSummary.Item]()

        if !hasVisibleProvider || isClaudeVisible {
            for metric in MenuBarMetric.allCases
            where metric != .hidden && claudeMetrics.contains(metric) {
                let limit = selectedLimit(
                    metric: metric,
                    fiveHour: hasVisibleProvider ? claudeFiveHour : nil,
                    weekly: hasVisibleProvider ? claudeWeekly : nil,
                    fable: hasVisibleProvider ? claudeFable : nil
                )
                if let value = providerValue(
                    metric: metric,
                    limit: limit,
                    labelsWeeklyWindow: true
                ) {
                    items.append(.init(
                        provider: .claude,
                        metric: metric,
                        value: value,
                        displayPercent: limit?.displayPercent
                    ))
                }
            }
        }

        if showsCodex, !hasVisibleProvider || isCodexVisible {
            let limit = hasVisibleProvider ? codexWeekly : nil
            if let value = providerValue(
                metric: .weekly,
                limit: limit,
                labelsWeeklyWindow: false
            ) {
                items.append(.init(
                    provider: .codex,
                    metric: .weekly,
                    value: value,
                    displayPercent: limit?.displayPercent
                ))
            }
        }
        return MenuBarSummary(items: items)
    }

    private static func providerValue(
        metric: MenuBarMetric,
        limit: UsageLimit?,
        labelsWeeklyWindow: Bool
    ) -> String? {
        let window: String?
        switch metric {
        case .fiveHour:
            window = "5h"
        case .weekly:
            window = labelsWeeklyWindow ? "7d" : nil
        case .fable:
            window = "Fable"
        case .hidden:
            return nil
        }

        let value = limit.map { "\(Int($0.displayPercent.rounded()))%" } ?? "--%"
        return [window, value]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func selectedLimit(
        metric: MenuBarMetric,
        fiveHour: UsageLimit?,
        weekly: UsageLimit?,
        fable: UsageLimit?
    ) -> UsageLimit? {
        switch metric {
        case .fiveHour: fiveHour
        case .weekly: weekly
        case .fable: fable
        case .hidden: nil
        }
    }
}
