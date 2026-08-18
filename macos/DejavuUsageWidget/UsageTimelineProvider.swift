import DejavuWidgetShared
import Foundation
import WidgetKit

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageWidgetEntry {
        UsageWidgetEntry.placeholder()
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (UsageWidgetEntry) -> Void
    ) {
        if context.isPreview {
            completion(.gallerySample())
        } else {
            completion(Self.currentEntry())
        }
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<UsageWidgetEntry>) -> Void
    ) {
        let now = Date()
        let entry = Self.currentEntry(now: now)
        let nextRefresh = now.addingTimeInterval(WidgetConstants.timelineFallbackInterval)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private static func currentEntry(now: Date = Date()) -> UsageWidgetEntry {
        guard let store = WidgetSnapshotStore.appGroup(
            identifier: WidgetConstants.appGroupIdentifier()
        ) else {
            return UsageWidgetEntry(
                date: now,
                content: .unavailable(.missing),
                isPlaceholder: false
            )
        }

        let content: UsageWidgetEntry.Content = switch store.read(now: now) {
        case let .snapshot(snapshot):
            .snapshot(snapshot)
        case .missing:
            .unavailable(.missing)
        case .stale:
            .unavailable(.stale)
        case .invalid, .unsupportedSchema:
            .unavailable(.invalid)
        }

        return UsageWidgetEntry(date: now, content: content, isPlaceholder: false)
    }
}
