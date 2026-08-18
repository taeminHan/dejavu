import DejavuDomain
import SwiftUI

/// A compact, optional companion to the menu-bar item.
///
/// The panel deliberately uses system typography, semantic foreground styles,
/// and a standard material. Provider identity uses the same monochrome marks
/// as every other compact macOS surface.
struct ModernWidgetView: View {
    @ObservedObject var model: AppModel
    let layout: WidgetLayoutMetrics
    let onOpenDetails: () -> Void

    var body: some View {
        Group {
            if orderedProviders.isEmpty {
                emptyState
            } else if layout.effectiveLayout == .twoRows {
                VStack(spacing: layout.providerGap) {
                    providerViews
                }
            } else {
                HStack(spacing: layout.providerGap) {
                    providerViews
                }
            }
        }
        .padding(layout.contentPadding)
        .frame(
            width: layout.panelWidth,
            height: layout.panelHeight,
            alignment: .center
        )
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(overlayBackgroundColor)
                .opacity(model.widgetOpacity)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(overlayTextColor.opacity(0.18), lineWidth: 1)
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture(perform: onOpenDetails)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dejavu usage widget")
        .accessibilityAction(named: "Open usage details", onOpenDetails)
        .help("Open Dejavu usage details")
    }

    @ViewBuilder
    private var providerViews: some View {
        ForEach(orderedProviders) { provider in
            let limits = compactLimits(for: provider)
            providerView(provider, limits: limits)
                .frame(width: providerContentWidth(for: provider))
        }
    }

    private var emptyState: some View {
        Label("Connect Claude or Codex", systemImage: "link.badge.plus")
            .font(.callout)
            .foregroundStyle(overlayTextColor.opacity(0.78))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func providerView(
        _ provider: UsageProviderViewState,
        limits: [UsageLimitViewState]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ProviderBrandIcon(provider: provider.kind.brand, size: 13)
                    .foregroundStyle(overlayTextColor.opacity(0.78))
                Spacer(minLength: 4)
                Text(LocalizedStringKey(provider.status.displayName))
                    .font(.caption2)
                    .foregroundStyle(overlayTextColor.opacity(0.72))
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: layout.metricGap) {
                ForEach(limits) { limit in
                    metricView(limit)
                        .frame(
                            width: metricWidth(
                                for: limits.count,
                                provider: provider
                            )
                        )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(provider.kind.rawValue)
        .accessibilityValue(
            limits
                .map { "\($0.label), \($0.displayText)" }
                .joined(separator: ", ")
        )
    }

    private func providerContentWidth(for provider: UsageProviderViewState) -> CGFloat {
        layout.providerContentWidth(for: provider.kind.providerID)
    }

    private func metricWidth(
        for count: Int,
        provider: UsageProviderViewState
    ) -> CGFloat {
        count == 1 ? providerContentWidth(for: provider) : layout.metricCellWidth
    }

    private func metricView(_ limit: UsageLimitViewState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(LocalizedStringKey(limit.label))
                    .font(.caption2)
                    .foregroundStyle(overlayTextColor.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 1)
                Text(limit.displayText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(
                        usageColor(
                            for: limit.displayPercent,
                            enabled: model.useThresholdColors,
                            normalColor: overlayAccentColor
                        )
                    )
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            if model.showProgress, let percent = limit.displayPercent {
                ProgressView(value: percent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(
                        usageProgressColor(
                            for: percent,
                            enabled: model.useThresholdColors,
                            normalColor: overlayAccentColor
                        )
                    )
                    .controlSize(.mini)
                    .accessibilityLabel(limit.label)
                    .accessibilityValue(limit.displayText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var orderedProviders: [UsageProviderViewState] {
        let providers = Dictionary(
            uniqueKeysWithValues: model.visibleProviders.map { ($0.kind.providerID, $0) }
        )
        return layout.providerOrder.compactMap { id in
            switch id {
            case .claude:
                providers[.claude]
            case .codex:
                providers[.codex]
            }
        }
    }

    private func compactLimits(for provider: UsageProviderViewState) -> [UsageLimitViewState] {
        guard provider.kind == .claude else { return provider.limits }

        let standardLimits = provider.limits.filter { $0.id != "claude-fable" }
        guard let fable = provider.limits.first(where: { $0.id == "claude-fable" }) else {
            return standardLimits
        }
        guard model.extendedFableAccessEnabled || fable.displayPercent != nil else {
            return standardLimits
        }
        return standardLimits + [fable]
    }

    private var overlayBackgroundColor: Color {
        Color(dejavuHex: model.backgroundColor) ?? .black
    }

    private var overlayAccentColor: Color {
        Color(dejavuHex: model.accentColor) ?? .accentColor
    }

    private var overlayTextColor: Color {
        Color(dejavuHex: model.textColor) ?? .primary
    }
}
