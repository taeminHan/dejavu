import Foundation

public enum UsageProviderID: String, Codable, CaseIterable, Sendable {
    case claude
    case codex
}
public struct ServiceVisibility: Codable, Hashable, Sendable {
    public let showClaude: Bool
    public let showCodex: Bool

    public init(showClaude: Bool, showCodex: Bool) {
        self.showClaude = showClaude
        self.showCodex = showCodex
    }

    public var providerCount: Int {
        (showClaude ? 1 : 0) + (showCodex ? 1 : 0)
    }
}

public enum ServiceVisibilityResolver {
    public static func resolve(mode: ServiceDisplayMode, state: ApplicationState) -> ServiceVisibility {
        resolve(
            mode: mode,
            claudeAvailable: state.claudeSnapshot != nil || state.claudeStatus == .ready,
            codexAvailable: state.codexSnapshot != nil || state.codexStatus == .ready
        )
    }

    public static func resolve(
        mode: ServiceDisplayMode,
        claudeAvailable: Bool,
        codexAvailable: Bool
    ) -> ServiceVisibility {
        switch mode {
        case .autoDetect:
            ServiceVisibility(showClaude: claudeAvailable, showCodex: codexAvailable)
        case .claudeAndCodex:
            ServiceVisibility(showClaude: true, showCodex: true)
        case .claudeOnly:
            ServiceVisibility(showClaude: true, showCodex: false)
        case .codexOnly:
            ServiceVisibility(showClaude: false, showCodex: true)
        }
    }
}

/// The seven required forced/automatic states used by layout probes.
public enum WidgetServiceState: String, CaseIterable, Sendable {
    case forcedBoth
    case forcedClaude
    case forcedCodex
    case autoNone
    case autoClaude
    case autoCodex
    case autoBoth

    public var visibility: ServiceVisibility {
        switch self {
        case .forcedBoth, .autoBoth:
            ServiceVisibility(showClaude: true, showCodex: true)
        case .forcedClaude, .autoClaude:
            ServiceVisibility(showClaude: true, showCodex: false)
        case .forcedCodex, .autoCodex:
            ServiceVisibility(showClaude: false, showCodex: true)
        case .autoNone:
            ServiceVisibility(showClaude: false, showCodex: false)
        }
    }
}
