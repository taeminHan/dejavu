import DejavuWidgetShared
import Foundation
import WidgetKit

struct UsageWidgetEntry: TimelineEntry, Hashable, Sendable {
    enum UnavailableReason: Hashable, Sendable {
        case missing
        case stale
        case invalid
    }

    enum Content: Hashable, Sendable {
        case snapshot(WidgetUsageSnapshot)
        case unavailable(UnavailableReason)
    }

    let date: Date
    let content: Content
    let isPlaceholder: Bool

    static func placeholder(date: Date = Date()) -> Self {
        Self(
            date: date,
            content: .snapshot(
                WidgetUsageSnapshot(
                    updatedAt: date,
                    claude: WidgetClaudeSnapshot(
                        status: .loading,
                        fiveHourPercent: nil,
                        weeklyPercent: nil
                    ),
                    codex: WidgetCodexSnapshot(
                        status: .loading,
                        percent: nil
                    )
                )
            ),
            isPlaceholder: true
        )
    }

    static func gallerySample(date: Date = Date()) -> Self {
        Self(
            date: date,
            content: .snapshot(
                WidgetUsageSnapshot(
                    updatedAt: date,
                    claude: WidgetClaudeSnapshot(
                        status: .ready,
                        fiveHourPercent: 38,
                        weeklyPercent: 61,
                        fablePercent: 12
                    ),
                    codex: WidgetCodexSnapshot(
                        status: .ready,
                        percent: 47
                    )
                )
            ),
            isPlaceholder: false
        )
    }
}
