import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private let pages = OnboardingPage.all

    var body: some View {
        VStack(spacing: 0) {
            onboardingContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 48)
                .padding(.vertical, 30)

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

                Button(page == pages.count - 1 ? "Done" : "Continue") {
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
        .frame(minWidth: 600, minHeight: 420)
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
                    detail: "Click the menu bar item to open the standard Dejavu menu."
                )
                OnboardingItem(
                    symbol: "rectangle.on.rectangle",
                    title: "Two optional widgets",
                    detail: "Use the floating overlay or add Dejavu from the macOS widget gallery."
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
                OnboardingProviderItem(
                    provider: .claude,
                    detail: "Choose the 5h, weekly, Fable, or hidden menu bar metric in Settings."
                )
                OnboardingProviderItem(
                    provider: .codex,
                    detail: "Show Codex usage in the menu bar, or hide it."
                )
                Label("You can change these choices later in Settings.", systemImage: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
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
