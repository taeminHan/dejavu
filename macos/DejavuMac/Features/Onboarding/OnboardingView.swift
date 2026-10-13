import DejavuDomain
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let onFinish: () -> Void

    @State private var page = 0

    private let pages = OnboardingPage.all

    init(model: AppModel, onFinish: @escaping () -> Void, initialPage: Int = 0) {
        self.model = model
        self.onFinish = onFinish
        _page = State(initialValue: min(2, max(0, initialPage)))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                onboardingContent
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 10) {
                Text(verbatim: "\(page + 1) / \(pages.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Onboarding progress")
                    .accessibilityValue(Text(verbatim: "\(page + 1) / \(pages.count)"))

                Spacer()

                if page < pages.count - 1 {
                    Button("Skip") {
                        onFinish()
                    }
                }

                if page > 0 {
                    Button("Back") {
                        page -= 1
                    }
                }

                Button(LocalizedStringKey(page == pages.count - 1 ? "Done" : "Continue")) {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        page += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 600, minHeight: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var onboardingContent: some View {
        VStack(spacing: 0) {
            Image(systemName: pages[page].symbol)
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(LocalizedStringKey(pages[page].title))
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Text(LocalizedStringKey(pages[page].detail))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
                .padding(.top, 8)

            pageContent
                .frame(maxWidth: 500)
                .padding(.top, 26)
        }
        .id(page)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case 0:
            VStack(alignment: .leading, spacing: 16) {
                OnboardingItem(
                    symbol: "menubar.rectangle",
                    title: "Menu bar summary",
                    detail: "See Claude 5h and Codex usage at a glance."
                )
                OnboardingItem(
                    symbol: "cursorarrow.click",
                    title: "One-click access",
                    detail: "Click the menu bar item to open details and controls."
                )
                OnboardingItem(
                    symbol: "rectangle.on.rectangle",
                    title: "Optional overlay",
                    detail: "Use the menu bar on its own, or enable the floating overlay in Settings."
                )
            }

        case 1:
            VStack(alignment: .leading, spacing: 16) {
                OnboardingItem(
                    symbol: "key.slash",
                    title: "Credentials are never stored",
                    detail: "Codex credentials are not read. Optional Fable access uses the Claude Code Keychain only after you enable it."
                )
                OnboardingItem(
                    symbol: "text.bubble",
                    title: "No conversations",
                    detail: "Prompts, transcripts, browser content, and working directories are not saved."
                )
                OnboardingItem(
                    symbol: "internaldrive",
                    title: "Stored locally",
                    detail: "Usage snapshots remain in your user Application Support directory."
                )
            }

        default:
            VStack(alignment: .leading, spacing: 16) {
                providerSetup(.claude)
                providerSetup(.codex)
                Label("You can change these choices later in Settings.", systemImage: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
    }

    private func providerSetup(_ provider: ProviderBrand) -> some View {
        let status = provider == .claude ? model.claudeStatus : model.codexStatus
        let message = provider == .claude ? model.domainState.claudeMessage : model.domainState.codexMessage
        let issue = provider == .claude ? model.domainState.claudeIssue : model.domainState.codexIssue
        return GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProviderBrandLabel(provider: provider, iconSize: 18)
                    Spacer()
                    Text(LocalizedStringKey(status.displayName)).foregroundStyle(.secondary)
                }
                Text(LocalizedStringKey(message)).font(.callout).foregroundStyle(.secondary)
                if provider == .claude, status != .ready {
                    HStack {
                        if model.claudeConnectionState != .connected {
                            Button("Connect Claude Status Line…") { model.connectClaudeStatusLine() }
                                .disabled(model.claudeConnectionState.isBusy)
                        }
                        if status == .loginRequired || (status == .error && issue == nil) || model.claudeLoginPending {
                            Button(LocalizedStringKey(model.claudeLoginPending ? "Sign-in in progress…" : "Sign In…")) { model.loginClaude() }
                                .disabled(model.claudeLoginPending)
                        }
                    }
                    Text("Usage arrives after Claude Code receives its first API response. Connecting does not send a model request.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if provider == .codex, status == .loginRequired || (status == .error && issue == nil) || model.codexLoginPending {
                    HStack {
                        Button(LocalizedStringKey(model.codexLoginPending ? "Reopen Browser…" : "Sign In…")) { model.loginCodex() }
                        if model.codexLoginPending {
                            Button("Cancel") { model.cancelCodexLogin() }
                        }
                    }
                }
                if status == .unavailable || status == .error {
                    Link("Installation Guide…", destination: URL(string: provider == .claude
                        ? "https://docs.anthropic.com/en/docs/claude-code/getting-started"
                        : "https://help.openai.com/en/articles/11096431")!)
                }
                if let loginMessage = provider == .claude ? model.claudeLoginMessage : model.codexLoginMessage {
                    Text(LocalizedStringKey(loginMessage)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

private struct OnboardingProviderItem: View {
    let provider: ProviderBrand
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderBrandIcon(provider: provider, size: 22)
                .foregroundStyle(.tint)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(provider.name)
                    .font(.headline)
                Text(LocalizedStringKey(detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let detail: String

    static let all = [
        OnboardingPage(
            symbol: "menubar.rectangle",
            title: "Usage at a glance",
            detail: "Dejavu is a native menu bar companion for local Claude and Codex usage."
        ),
        OnboardingPage(
            symbol: "hand.raised.fill",
            title: "Private by design",
            detail: "Usage stays on this Mac. Dejavu never stores credentials or collects conversation content."
        ),
        OnboardingPage(
            symbol: "checkmark.circle",
            title: "Ready when you are",
            detail: "Start with sensible defaults. Provider metrics and the optional widget remain under your control."
        )
    ]
}

private struct OnboardingItem: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                Text(LocalizedStringKey(detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 26)
        }
        .accessibilityElement(children: .combine)
    }
}
