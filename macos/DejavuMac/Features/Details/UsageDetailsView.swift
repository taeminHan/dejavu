import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void

    var body: some View {
        Group {
            if model.visibleProviders.isEmpty {
                ContentUnavailableView(
                    "No provider connected",
                    systemImage: "link.badge.plus",
                    description: Text("Connect a local provider in Settings.")
                )
            } else {
                List {
                    statusSection

                    ForEach(model.visibleProviders) { provider in
                        providerSection(provider)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refresh(force: true)
                } label: {
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isRefreshing)
                .help("Refresh local usage")

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Settings")
            }
        }
        .navigationTitle("Usage details")
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Updated") {
                Text(updatedText)
                    .foregroundStyle(.secondary)
            }

        }
    }

    private var updatedText: String {
        guard let updatedAt = model.state.updatedAt else { return "--" }
        return updatedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private func providerSection(_ provider: UsageProviderViewState) -> some View {
        Section {
            ForEach(provider.limits) { limit in
                limitRow(limit)
            }

            if provider.kind == .codex {
                resetCreditRow(provider)
            }

            if let message = provider.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Provider note")
                    .accessibilityValue(message)
            }
        } header: {
            HStack(spacing: 6) {
                ProviderBrandLabel(
                    provider: provider.kind.brand,
                    spacing: 5,
                    iconSize: 14
                )
                Text(LocalizedStringKey(provider.status.displayName))
                    .foregroundStyle(.secondary)
                Spacer()
                if let planName = provider.planName {
                    Text(planName)
                        .foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
        }
    }

    private func limitRow(_ limit: UsageLimitViewState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent {
                Text(limit.displayText)
                    .font(.body.weight(.medium).monospacedDigit())
                    .foregroundStyle(
                        usageColor(
                            for: limit.displayPercent,
                            enabled: model.settings.usesThresholdColors
                        )
                    )
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey(limit.label))
                    if let resetsAt = limit.resetsAt {
                        Text("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let percent = limit.displayPercent {
                ProgressView(value: percent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(
                        usageProgressColor(
                            for: percent,
                            enabled: model.settings.usesThresholdColors
                        )
                    )
                    .accessibilityLabel(limit.label)
                    .accessibilityValue(limit.displayText)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resetCreditRow(_ provider: UsageProviderViewState) -> some View {
        LabeledContent {
            if let credits = provider.resetCredits {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(credits)")
                        .font(.body.weight(.medium).monospacedDigit())
                    if let expiry = provider.resetCreditsExpireAt {
                        Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Reset credits", systemImage: "arrow.counterclockwise.circle")
        }
        .accessibilityElement(children: .combine)
    }
}
