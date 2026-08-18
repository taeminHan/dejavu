import DejavuDomain
import DejavuWidgetShared
import SwiftUI
import WidgetKit

struct UsageWidgetView: View {
    let entry: UsageWidgetEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.content {
            case let .snapshot(snapshot):
                snapshotView(snapshot)
            case let .unavailable(reason):
                unavailableView(reason)
            }
        }
        .placeholderRedacted(entry.isPlaceholder)
        .widgetURL(URL(string: "dejavu://usage"))
    }

    private func snapshotView(_ snapshot: WidgetUsageSnapshot) -> some View {
        let providers = displayProviders(snapshot)

        return VStack(alignment: .leading, spacing: family == .systemSmall ? 9 : 12) {
            header(updatedAt: snapshot.updatedAt)

            if providers.isEmpty {
                Spacer(minLength: 0)
                Label("No providers connected", systemImage: "link.badge.plus")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            } else if family == .systemSmall {
                VStack(spacing: 9) {
                    ForEach(providers) { provider in
                        CompactProviderRow(provider: provider)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(providers) { provider in
                        DetailedProviderRow(provider: provider)
                    }
                }
            }
        }
    }

    private func unavailableView(_ reason: UsageWidgetEntry.UnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(updatedAt: nil)
            Spacer(minLength: 0)
            Label(unavailableTitle(reason), systemImage: unavailableSymbol(reason))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Open Dejavu to refresh")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
    }

    private func header(updatedAt: Date?) -> some View {
        HStack(spacing: 6) {
            Label("Dejavu", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .labelStyle(.titleAndIcon)
            Spacer(minLength: 4)
            if let updatedAt, !entry.isPlaceholder {
                Text(updatedAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private func displayProviders(_ snapshot: WidgetUsageSnapshot) -> [DisplayProvider] {
        var providers = [DisplayProvider]()
        if let claude = snapshot.claude {
            var metrics = [
                DisplayMetric(
                    id: .claudeFiveHour,
                    label: "5h",
                    percent: claude.fiveHourPercent
                ),
                DisplayMetric(
                    id: .claudeWeekly,
                    label: "Week",
                    percent: claude.weeklyPercent
                )
            ]
            if family == .systemMedium, let fablePercent = claude.fablePercent {
                metrics.append(
                    DisplayMetric(
                        id: .claudeFable,
                        label: "Fable",
                        percent: fablePercent
                    )
                )
            }
            providers.append(
                DisplayProvider(kind: .claude, status: claude.status, metrics: metrics)
            )
        }
        if let codex = snapshot.codex {
            providers.append(
                DisplayProvider(
                    kind: .codex,
                    status: codex.status,
                    metrics: [
                        DisplayMetric(
                            id: .codex,
                            label: "Codex",
                            percent: codex.percent,
                            showsLabel: false
                        )
                    ]
                )
            )
        }
        return providers
    }

    private func unavailableTitle(_ reason: UsageWidgetEntry.UnavailableReason) -> LocalizedStringKey {
        switch reason {
        case .missing:
            "Usage is not available yet"
        case .stale:
            "Usage needs an update"
        case .invalid:
            "Usage data is unavailable"
        }
    }

    private func unavailableSymbol(_ reason: UsageWidgetEntry.UnavailableReason) -> String {
        switch reason {
        case .missing:
            "chart.bar.xaxis"
        case .stale:
            "clock.badge.exclamationmark"
        case .invalid:
            "exclamationmark.triangle"
        }
    }
}

private extension View {
    @ViewBuilder
    func placeholderRedacted(_ isPlaceholder: Bool) -> some View {
        if isPlaceholder {
            redacted(reason: .placeholder)
        } else {
            self
        }
    }
}

private struct CompactProviderRow: View {
    let provider: DisplayProvider

    var body: some View {
        HStack(spacing: 5) {
            ProviderBrandIcon(provider: provider.brand, size: 14)
                .foregroundStyle(.secondary)

            Spacer(minLength: 2)

            ForEach(provider.metrics) { metric in
                InlineMetric(
                    label: metric.label,
                    percent: metric.percent,
                    showsLabel: metric.showsLabel
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(provider.name)
    }
}

private struct DetailedProviderRow: View {
    let provider: DisplayProvider

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ProviderBrandLabel(
                    provider: provider.brand,
                    spacing: 4,
                    iconSize: 14
                )
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                StatusSymbol(status: provider.status)
            }
            .frame(width: 76, alignment: .leading)

            ForEach(provider.metrics) { metric in
                ProgressMetric(
                    label: metric.label,
                    percent: metric.percent,
                    showsLabel: metric.showsLabel
                )
            }
        }
    }
}

private struct InlineMetric: View {
    let label: LocalizedStringKey
    let percent: Double?
    let showsLabel: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if showsLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(percentText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(usageColor(for: percent))
                .privacySensitive()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percentAccessibilityValue)
    }

    private var percentText: String {
        guard let percent else { return "--%" }
        return "\(Int(percent.rounded()))%"
    }

    private var percentAccessibilityValue: String {
        guard let percent else { return String(localized: "Unavailable") }
        return String(localized: "\(Int(percent.rounded())) percent")
    }
}

private struct ProgressMetric: View {
    let label: LocalizedStringKey
    let percent: Double?
    let showsLabel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if showsLabel {
                    Text(label)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 2)
                Text(percentText)
                    .monospacedDigit()
                    .fontWeight(.semibold)
                    .foregroundStyle(usageColor(for: percent))
                    .privacySensitive()
            }
            .font(.caption)

            if let percent {
                ProgressView(value: percent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(usageProgressColor(for: percent))
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(percentAccessibilityValue)
    }

    private var percentText: String {
        guard let percent else { return "--%" }
        return "\(Int(percent.rounded()))%"
    }

    private var percentAccessibilityValue: String {
        guard let percent else { return String(localized: "Unavailable") }
        return String(localized: "\(Int(percent.rounded())) percent")
    }
}

private struct StatusSymbol: View {
    let status: UsageStatus

    var body: some View {
        Image(systemName: symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(accessibilityLabel)
    }

    private var symbolName: String {
        switch status {
        case .loading:
            "arrow.triangle.2.circlepath"
        case .ready:
            "checkmark.circle"
        case .loginRequired:
            "person.crop.circle.badge.exclamationmark"
        case .rateLimited:
            "hourglass"
        case .offline:
            "wifi.slash"
        case .error:
            "exclamationmark.triangle"
        case .unavailable:
            "circle.dashed"
        }
    }

    private var accessibilityLabel: LocalizedStringKey {
        switch status {
        case .loading:
            "Refreshing"
        case .ready:
            "Ready"
        case .loginRequired:
            "Login required"
        case .rateLimited:
            "Rate limited"
        case .offline:
            "Offline"
        case .error:
            "Unavailable"
        case .unavailable:
            "Not connected"
        }
    }
}

private struct DisplayProvider: Identifiable {
    enum Kind: String {
        case claude
        case codex
    }

    let kind: Kind
    let status: UsageStatus
    let metrics: [DisplayMetric]

    var id: Kind { kind }

    var name: LocalizedStringKey {
        switch kind {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    var brand: ProviderBrand {
        switch kind {
        case .claude: .claude
        case .codex: .codex
        }
    }
}

private struct DisplayMetric: Identifiable {
    enum ID: String {
        case claudeFiveHour
        case claudeWeekly
        case claudeFable
        case codex
    }

    let id: ID
    let label: LocalizedStringKey
    let percent: Double?
    let showsLabel: Bool

    init(
        id: ID,
        label: LocalizedStringKey,
        percent: Double?,
        showsLabel: Bool = true
    ) {
        self.id = id
        self.label = label
        self.percent = percent
        self.showsLabel = showsLabel
    }
}
