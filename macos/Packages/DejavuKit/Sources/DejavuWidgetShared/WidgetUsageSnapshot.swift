import DejavuDomain
import Foundation

public struct WidgetClaudeSnapshot: Codable, Hashable, Sendable {
    public let status: UsageStatus
    public let fiveHourPercent: Double?
    public let weeklyPercent: Double?
    public let fablePercent: Double?

    public init(
        status: UsageStatus,
        fiveHourPercent: Double?,
        weeklyPercent: Double?,
        fablePercent: Double? = nil
    ) {
        self.status = status
        self.fiveHourPercent = Self.normalizedPercent(fiveHourPercent)
        self.weeklyPercent = Self.normalizedPercent(weeklyPercent)
        self.fablePercent = Self.normalizedPercent(fablePercent)
    }

    public init(
        status: UsageStatus,
        fiveHour: UsageLimit?,
        weekly: UsageLimit?,
        fable: UsageLimit? = nil
    ) {
        self.init(
            status: status,
            fiveHourPercent: fiveHour?.displayPercent,
            weeklyPercent: weekly?.displayPercent,
            fablePercent: fable?.displayPercent
        )
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case fiveHourPercent
        case weeklyPercent
        case fablePercent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(UsageStatus.self, forKey: .status)
        fiveHourPercent = Self.normalizedPercent(
            try container.decodeIfPresent(Double.self, forKey: .fiveHourPercent)
        )
        weeklyPercent = Self.normalizedPercent(
            try container.decodeIfPresent(Double.self, forKey: .weeklyPercent)
        )
        fablePercent = Self.normalizedPercent(
            try container.decodeIfPresent(Double.self, forKey: .fablePercent)
        )
    }

    private static func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return UsageLimit.clampedDisplayPercent(value)
    }
}

/// The widget's complete Codex projection: one weekly-backed percentage.
/// Raw app-server primary/five-hour windows never cross the App Group boundary.
public struct WidgetCodexSnapshot: Codable, Hashable, Sendable {
    public let status: UsageStatus
    public let percent: Double?

    public init(status: UsageStatus, percent: Double?) {
        self.status = status
        self.percent = Self.normalizedPercent(percent)
    }

    public init(status: UsageStatus, weekly: UsageLimit?) {
        self.init(status: status, percent: weekly?.displayPercent)
    }

    private enum CodingKeys: String, CodingKey {
        case status
        case percent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(UsageStatus.self, forKey: .status)
        percent = Self.normalizedPercent(
            try container.decodeIfPresent(Double.self, forKey: .percent)
        )
    }

    private static func normalizedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return UsageLimit.clampedDisplayPercent(value)
    }
}

/// The complete allow-list shared with the WidgetKit extension.
///
/// Keep this model intentionally smaller than diagnostics. It must never grow
/// credential, account, path, plan, reset-credit, prompt, or message fields.
public struct WidgetUsageSnapshot: Codable, Hashable, Sendable {
    /// Version 2 replaces the generic provider payload with distinct Claude
    /// and single-percentage Codex payloads. Version 1 must not be reused.
    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let updatedAt: Date
    public let claude: WidgetClaudeSnapshot?
    public let codex: WidgetCodexSnapshot?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case claude
        case codex
    }

    public init(
        updatedAt: Date,
        claude: WidgetClaudeSnapshot?,
        codex: WidgetCodexSnapshot?
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.updatedAt = updatedAt
        self.claude = claude
        self.codex = codex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedSchemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        switch encodedSchemaVersion {
        case 1:
            claude = try container.decodeIfPresent(
                WidgetClaudeSnapshot.self,
                forKey: .claude
            )
            let legacyCodex = try container.decodeIfPresent(
                LegacyWidgetProviderSnapshot.self,
                forKey: .codex
            )
            codex = legacyCodex.map {
                WidgetCodexSnapshot(status: $0.status, percent: $0.weeklyPercent)
            }
        case Self.currentSchemaVersion:
            claude = try container.decodeIfPresent(
                WidgetClaudeSnapshot.self,
                forKey: .claude
            )
            codex = try container.decodeIfPresent(
                WidgetCodexSnapshot.self,
                forKey: .codex
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported widget snapshot schema"
            )
        }

        // A decoded legacy payload is normalized immediately. Re-encoding can
        // therefore never write the removed Codex five-hour field again.
        schemaVersion = Self.currentSchemaVersion
    }

    public static func supports(schemaVersion: Int) -> Bool {
        schemaVersion == 1 || schemaVersion == currentSchemaVersion
    }

    public init(
        state: ApplicationState,
        updatedAt: Date,
        includesClaude: Bool,
        includesCodex: Bool
    ) {
        self.init(
            updatedAt: updatedAt,
            claude: includesClaude ? WidgetClaudeSnapshot(
                status: state.claudeStatus,
                fiveHour: state.claudeSnapshot?.fiveHour,
                weekly: state.claudeSnapshot?.weekly,
                fable: state.claudeSnapshot?.fable
            ) : nil,
            codex: includesCodex ? WidgetCodexSnapshot(
                status: state.codexStatus,
                weekly: state.codexSnapshot?.weekly
            ) : nil
        )
    }
}

private struct LegacyWidgetProviderSnapshot: Decodable {
    let status: UsageStatus
    let weeklyPercent: Double?

    private enum CodingKeys: String, CodingKey {
        case status
        case weeklyPercent
    }
}
