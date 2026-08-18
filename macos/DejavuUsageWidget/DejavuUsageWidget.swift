import DejavuWidgetShared
import SwiftUI
import WidgetKit

struct DejavuUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WidgetConstants.usageKind,
            provider: UsageTimelineProvider()
        ) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Dejavu Usage")
        .description("Your local Claude and Codex usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
