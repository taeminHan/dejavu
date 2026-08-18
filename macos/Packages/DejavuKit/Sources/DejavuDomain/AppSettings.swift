import Foundation

public enum PrimaryMetric: String, Codable, CaseIterable, Sendable {
    case fiveHour
    case weekly
    case codex
}

public enum MenuBarMetric: String, Codable, CaseIterable, Sendable {
    case fiveHour
    case weekly
    case fable
    case hidden
}

public enum UsageColorLevel: String, Codable, CaseIterable, Sendable {
    case normal
    case warning
    case danger

    public static func level(for displayPercent: Double?) -> Self {
        guard let displayPercent else { return .normal }
        if displayPercent >= 90 { return .danger }
        if displayPercent >= 70 { return .warning }
        return .normal
    }
}

public enum TrayIconStyle: String, Codable, CaseIterable, Sendable {
    case mark
    case percentage
    case hidden
}

public enum WidgetDensity: String, Codable, CaseIterable, Sendable {
    case small
    case compact
    case comfortable
}

public enum WidgetLayout: String, Codable, CaseIterable, Sendable {
    case singleRow
    case twoRows
}

public enum ServiceDisplayMode: String, Codable, CaseIterable, Sendable {
    case autoDetect
    case claudeAndCodex
    case claudeOnly
    case codexOnly
}

public enum WidgetPlacement: String, Codable, CaseIterable, Sendable {
    case topRight
    case bottomRight
    case custom
}

public enum ThemePreference: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public enum WidgetVisualTheme: String, Codable, CaseIterable, Sendable {
    case modern
}

public struct WidgetPosition: Codable, Hashable, Sendable {
    public var displayIdentifier: String?
    public var topLeftX: Double
    public var topLeftY: Double

    public init(displayIdentifier: String?, topLeftX: Double, topLeftY: Double) {
        self.displayIdentifier = displayIdentifier
        self.topLeftX = topLeftX
        self.topLeftY = topLeftY
    }

    fileprivate func normalized() -> Self? {
        guard topLeftX.isFinite, topLeftY.isFinite else { return nil }
        var result = self
        result.displayIdentifier = Self.normalizedIdentifier(displayIdentifier)
        return result
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(128))
    }
}

public struct AppSettings: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var primaryMetric: PrimaryMetric
    public var claudeMenuBarMetric: MenuBarMetric
    public var codexMenuBarMetric: MenuBarMetric
    public var claudeMenuBarMetrics: [MenuBarMetric]
    public var showsCodexInMenuBar: Bool
    public var showProgress: Bool
    public var showsWidget: Bool
    public var extendedFableAccessEnabled: Bool
    public var widgetOpacity: Double
    public var customPosition: WidgetPosition?
    public var backgroundColor: String
    public var accentColor: String
    public var textColor: String
    public var useThresholdColors: Bool
    public var refreshIntervalSeconds: Int
    public var trayIconStyle: TrayIconStyle
    public var widgetDensity: WidgetDensity
    public var widgetLayout: WidgetLayout
    public var serviceDisplayMode: ServiceDisplayMode
    public var widgetPlacement: WidgetPlacement
    public var appearance: ThemePreference
    public var widgetTheme: WidgetVisualTheme
    public var firstRunCompleted: Bool
    public var automaticUpdateChecksEnabled: Bool
    public var lastNotifiedUpdateVersion: String?

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        primaryMetric: PrimaryMetric = .fiveHour,
        claudeMenuBarMetric: MenuBarMetric = .fiveHour,
        codexMenuBarMetric: MenuBarMetric = .weekly,
        claudeMenuBarMetrics: [MenuBarMetric]? = nil,
        showsCodexInMenuBar: Bool? = nil,
        showProgress: Bool = true,
        showsWidget: Bool = true,
        extendedFableAccessEnabled: Bool = false,
        widgetOpacity: Double = 0.9,
        customPosition: WidgetPosition? = nil,
        backgroundColor: String = "#1E1E20",
        accentColor: String = "#3A96F6",
        textColor: String = "#AEAEB4",
        useThresholdColors: Bool = true,
        refreshIntervalSeconds: Int = 60,
        trayIconStyle: TrayIconStyle = .mark,
        widgetDensity: WidgetDensity = .compact,
        widgetLayout: WidgetLayout = .singleRow,
        serviceDisplayMode: ServiceDisplayMode = .autoDetect,
        widgetPlacement: WidgetPlacement = .bottomRight,
        appearance: ThemePreference = .system,
        widgetTheme: WidgetVisualTheme = .modern,
        firstRunCompleted: Bool = false,
        automaticUpdateChecksEnabled: Bool = true,
        lastNotifiedUpdateVersion: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.primaryMetric = primaryMetric
        self.claudeMenuBarMetric = claudeMenuBarMetric
        self.codexMenuBarMetric = codexMenuBarMetric
        self.claudeMenuBarMetrics = claudeMenuBarMetrics
            ?? Self.legacyClaudeMetrics(claudeMenuBarMetric)
        self.showsCodexInMenuBar = showsCodexInMenuBar
            ?? (codexMenuBarMetric != .hidden)
        self.showProgress = showProgress
        self.showsWidget = showsWidget
        self.extendedFableAccessEnabled = extendedFableAccessEnabled
        self.widgetOpacity = widgetOpacity
        self.customPosition = customPosition
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.textColor = textColor
        self.useThresholdColors = useThresholdColors
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.trayIconStyle = trayIconStyle
        self.widgetDensity = widgetDensity
        self.widgetLayout = widgetLayout
        self.serviceDisplayMode = serviceDisplayMode
        self.widgetPlacement = widgetPlacement
        self.appearance = appearance
        self.widgetTheme = widgetTheme
        self.firstRunCompleted = firstRunCompleted
        self.automaticUpdateChecksEnabled = automaticUpdateChecksEnabled
        self.lastNotifiedUpdateVersion = lastNotifiedUpdateVersion
        normalize()
    }

    public mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        if codexMenuBarMetric == .fiveHour || codexMenuBarMetric == .fable {
            codexMenuBarMetric = .weekly
        }
        claudeMenuBarMetrics = Self.normalizedClaudeMetrics(claudeMenuBarMetrics)
        claudeMenuBarMetric = claudeMenuBarMetrics.first ?? .hidden
        codexMenuBarMetric = showsCodexInMenuBar ? .weekly : .hidden
        widgetOpacity = widgetOpacity.isFinite ? min(1, max(0.55, widgetOpacity)) : 0.9
        refreshIntervalSeconds = min(300, max(60, refreshIntervalSeconds))
        customPosition = customPosition?.normalized()
        backgroundColor = Self.normalizedColor(backgroundColor, fallback: "#1E1E20")
        accentColor = Self.normalizedColor(accentColor, fallback: "#3A96F6")
        textColor = Self.normalizedColor(textColor, fallback: "#AEAEB4")
        lastNotifiedUpdateVersion = Self.normalizedVersion(lastNotifiedUpdateVersion)
    }

    public func normalized() -> Self {
        var result = self
        result.normalize()
        return result
    }

    private static func normalizedColor(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard [7, 9].contains(trimmed.count), trimmed.first == "#" else { return fallback }
        let digits = trimmed.dropFirst()
        guard digits.unicodeScalars.allSatisfy({
            CharacterSet(charactersIn: "0123456789ABCDEF").contains($0)
        }) else { return fallback }
        return trimmed
    }

    private static func normalizedVersion(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(64))
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case primaryMetric
        case claudeMenuBarMetric
        case codexMenuBarMetric
        case claudeMenuBarMetrics
        case showsCodexInMenuBar
        case showProgress
        case showsWidget
        case extendedFableAccessEnabled
        case widgetOpacity
        case customPosition
        case backgroundColor
        case accentColor
        case textColor
        case useThresholdColors
        case refreshIntervalSeconds
        case trayIconStyle
        case widgetDensity
        case widgetLayout
        case serviceDisplayMode
        case widgetPlacement
        case appearance
        case widgetTheme
        case firstRunCompleted
        case automaticUpdateChecksEnabled
        case lastNotifiedUpdateVersion
    }

    public init(from decoder: Decoder) throws {
        let defaults = Self()
        let container = try decoder.container(keyedBy: CodingKeys.self)

        schemaVersion = (try? container.decode(Int.self, forKey: .schemaVersion)) ?? defaults.schemaVersion
        primaryMetric = Self.decodeEnum(PrimaryMetric.self, from: container, key: .primaryMetric)
            ?? defaults.primaryMetric
        claudeMenuBarMetric = Self.decodeEnum(MenuBarMetric.self, from: container, key: .claudeMenuBarMetric)
            ?? defaults.claudeMenuBarMetric
        codexMenuBarMetric = Self.decodeEnum(MenuBarMetric.self, from: container, key: .codexMenuBarMetric)
            ?? defaults.codexMenuBarMetric
        claudeMenuBarMetrics = (try? container.decode([MenuBarMetric].self, forKey: .claudeMenuBarMetrics))
            ?? Self.legacyClaudeMetrics(claudeMenuBarMetric)
        showsCodexInMenuBar = (try? container.decode(Bool.self, forKey: .showsCodexInMenuBar))
            ?? (codexMenuBarMetric != .hidden)
        showProgress = (try? container.decode(Bool.self, forKey: .showProgress)) ?? defaults.showProgress
        showsWidget = (try? container.decode(Bool.self, forKey: .showsWidget)) ?? defaults.showsWidget
        extendedFableAccessEnabled = (
            try? container.decode(Bool.self, forKey: .extendedFableAccessEnabled)
        ) ?? defaults.extendedFableAccessEnabled
        widgetOpacity = (try? container.decode(Double.self, forKey: .widgetOpacity)) ?? defaults.widgetOpacity
        customPosition = try? container.decode(WidgetPosition.self, forKey: .customPosition)
        backgroundColor = (try? container.decode(String.self, forKey: .backgroundColor))
            ?? defaults.backgroundColor
        accentColor = (try? container.decode(String.self, forKey: .accentColor)) ?? defaults.accentColor
        textColor = (try? container.decode(String.self, forKey: .textColor)) ?? defaults.textColor
        useThresholdColors = (try? container.decode(Bool.self, forKey: .useThresholdColors))
            ?? defaults.useThresholdColors
        refreshIntervalSeconds = (try? container.decode(Int.self, forKey: .refreshIntervalSeconds))
            ?? defaults.refreshIntervalSeconds
        trayIconStyle = Self.decodeEnum(TrayIconStyle.self, from: container, key: .trayIconStyle)
            ?? defaults.trayIconStyle
        widgetDensity = Self.decodeEnum(WidgetDensity.self, from: container, key: .widgetDensity)
            ?? defaults.widgetDensity
        widgetLayout = Self.decodeEnum(WidgetLayout.self, from: container, key: .widgetLayout)
            ?? defaults.widgetLayout
        serviceDisplayMode = Self.decodeEnum(ServiceDisplayMode.self, from: container, key: .serviceDisplayMode)
            ?? defaults.serviceDisplayMode
        widgetPlacement = Self.decodeEnum(WidgetPlacement.self, from: container, key: .widgetPlacement)
            ?? defaults.widgetPlacement
        appearance = Self.decodeEnum(ThemePreference.self, from: container, key: .appearance)
            ?? defaults.appearance
        widgetTheme = Self.decodeEnum(WidgetVisualTheme.self, from: container, key: .widgetTheme)
            ?? defaults.widgetTheme
        firstRunCompleted = (try? container.decode(Bool.self, forKey: .firstRunCompleted))
            ?? defaults.firstRunCompleted
        automaticUpdateChecksEnabled = (
            try? container.decode(Bool.self, forKey: .automaticUpdateChecksEnabled)
        ) ?? defaults.automaticUpdateChecksEnabled
        lastNotifiedUpdateVersion = try? container.decode(String.self, forKey: .lastNotifiedUpdateVersion)
        normalize()
    }

    private static func decodeEnum<Value>(
        _ type: Value.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Value? where Value: RawRepresentable, Value.RawValue == String {
        guard let rawValue = try? container.decode(String.self, forKey: key) else { return nil }
        return Value(rawValue: rawValue)
    }

    private static func legacyClaudeMetrics(_ metric: MenuBarMetric) -> [MenuBarMetric] {
        metric == .hidden ? [] : [metric]
    }

    private static func normalizedClaudeMetrics(_ metrics: [MenuBarMetric]) -> [MenuBarMetric] {
        MenuBarMetric.allCases.filter { metric in
            metric != .hidden && metrics.contains(metric)
        }
    }
}
