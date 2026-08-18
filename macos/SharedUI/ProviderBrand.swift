import SwiftUI

enum ProviderBrand: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: Self { self }

    var assetName: String {
        switch self {
        case .claude:
            "ClaudeSparkMenuBar"
        case .codex:
            "CodexMenuBar"
        }
    }

    var name: LocalizedStringKey {
        switch self {
        case .claude:
            "Claude"
        case .codex:
            "Codex"
        }
    }
}

struct ProviderBrandIcon: View {
    let provider: ProviderBrand
    var size: CGFloat = 16

    var body: some View {
        Image(provider.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct ProviderBrandLabel: View {
    let provider: ProviderBrand
    var spacing: CGFloat = 6
    var iconSize: CGFloat = 16

    var body: some View {
        HStack(spacing: spacing) {
            ProviderBrandIcon(provider: provider, size: iconSize)
            Text(provider.name)
        }
        .accessibilityElement(children: .combine)
    }
}
