import DejavuDomain
import SwiftUI

struct UsageDetailsView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void
    var onOpenConnections: (() -> Void)? = nil
    var onOpenUpdates: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Usage details").font(.headline)
                Spacer()
                Button {
                    model.refreshManually()
                } label: {
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(model.isRefreshing)
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Refresh local usage")
                .help("Refresh local usage")

                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Open Settings")
            }
            .padding(16)
            Divider()
            List {
                statusSection
                ForEach(model.visibleProviders) { provider in
                    providerSection(provider)
                }
                if model.claudeStatus != .ready {
                    recoverySection(for: .claude, status: model.claudeStatus, message: model.domainState.claudeMessage)
                }
                if model.codexStatus != .ready {
                    recoverySection(for: .codex, status: model.codexStatus, message: model.domainState.codexMessage)
                }
            }
            .listStyle(.inset)
        }
        .frame(minWidth: 420, minHeight: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Updated") {
                Text(updatedText)
                    .foregroundStyle(.secondary)
            }
            if let retryAt = model.domainState.retryAt {
                Label {
                    Text("Automatic retry at \(retryAt.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func recoverySection(for provider: ProviderBrand, status: UsageStatus, message: String) -> some View {
        let issue = provider == .claude ? model.domainState.claudeIssue : model.domainState.codexIssue
        return Section {
            if !message.isEmpty {
                Text(LocalizedStringKey(message)).font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                if provider == .claude {
                    if status == .unavailable || model.claudeConnectionState == .notChecked || model.claudeConnectionState == .disconnected {
                        Button("Connect Claude Status Line…") { model.connectClaudeStatusLine() }
                            .disabled(model.claudeConnectionState.isBusy)
                    }
                    if status == .loginRequired || (status == .error && issue == nil && model.domainState.claudeSnapshot == nil) || model.claudeLoginPending {
                        Button(LocalizedStringKey(model.claudeLoginPending ? "Sign-in in progress…" : "Sign In…")) { model.loginClaude() }
                            .disabled(model.claudeLoginPending)
                    }
                } else if status == .loginRequired || (status == .error && issue == nil && model.domainState.codexSnapshot == nil) || model.codexLoginPending {
                    Button(LocalizedStringKey(model.codexLoginPending ? "Reopen Browser…" : "Sign In…")) { model.loginCodex() }
                    if model.codexLoginPending {
                        Button("Cancel") { model.cancelCodexLogin() }
                    }
                }
                if status == .offline || status == .error || status == .rateLimited || status == .unavailable {
                    Button("Retry Now") { model.refreshManually() }.disabled(model.isRefreshing)
                }
            }
            if issue == .permissionDenied {
                Button("Review Connection Settings…", action: onOpenConnections ?? onOpenSettings)
            } else if issue == .responseChanged {
                Button("Review Update Settings…", action: onOpenUpdates ?? onOpenSettings)
            } else if issue == .tokenRefreshPending {
                Text("Open Claude Code once to refresh its session, then retry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = provider == .claude ? model.claudeLoginMessage : model.codexLoginMessage {
                Text(LocalizedStringKey(message)).font(.caption).foregroundStyle(.secondary)
            }
            if status == .unavailable {
                Link("Installation Guide…", destination: URL(string: provider == .claude
                    ? "https://docs.anthropic.com/en/docs/claude-code/getting-started"
                    : "https://help.openai.com/en/articles/11096431")!)
            }
        } header: {
            ProviderBrandLabel(provider: provider, iconSize: 14)
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
                Text(LocalizedStringKey(message))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Provider note")
                    .accessibilityValue(Text(LocalizedStringKey(message)))
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

            Gauge(value: limit.displayPercent ?? 0, in: 0...100) {
                EmptyView()
            }
                    .gaugeStyle(.linearCapacity)
                    .tint(
                        usageProgressColor(
                            for: limit.displayPercent,
                            enabled: model.settings.usesThresholdColors
                        )
                    )
                    .accessibilityLabel(Text(LocalizedStringKey(limit.label)))
                    .accessibilityValue(limit.displayText)
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
