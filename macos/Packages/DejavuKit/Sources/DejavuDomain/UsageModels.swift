import Foundation

public enum UsageStatus: String, Codable, CaseIterable, Sendable {
    case loading
    case ready
    case loginRequired
    case rateLimited
    case offline
    case error
    case unavailable

    public static func combined(claude: Self, codex: Self) -> Self {
        let statuses = [claude, codex]
        if statuses.contains(.ready) { return .ready }
        if statuses.contains(.loading) { return .loading }
        if statuses.contains(.rateLimited) { return .rateLimited }
        if statuses.contains(.offline) { return .offline }
        if statuses.allSatisfy({ $0 == .loginRequired }) { return .loginRequired }
        if statuses.allSatisfy({ $0 == .unavailable }) { return .unavailable }
        return .error
    }
}

public struct UsageLimit: Codable, Hashable, Sendable {
    public let percent: Double
    public let resetsAt: Date?

    public init(percent: Double, resetsAt: Date? = nil) {
        self.percent = percent
        self.resetsAt = resetsAt
    }

    /// The single value UI text and progress geometry must both consume.
    public var displayPercent: Double {
        Self.clampedDisplayPercent(percent)
    }

    public var progressFraction: Double {
        displayPercent / 100
    }

    public static func clampedDisplayPercent(_ value: Double) -> Double {
        if value.isNaN { return 0 }
        if value == .infinity { return 100 }
        if value == -.infinity { return 0 }
        return min(100, max(0, value))
    }
}

public enum ClaudeUsageSource: String, Codable, CaseIterable, Sendable {
    case statusLine
    case oauthUsage
}

public struct ClaudeUsageSnapshot: Codable, Hashable, Sendable {
    public let fiveHour: UsageLimit?
    public let weekly: UsageLimit?
    public let fable: UsageLimit?
    public let source: ClaudeUsageSource
    public let capturedAt: Date

    public init(
        fiveHour: UsageLimit?,
        weekly: UsageLimit?,
        fable: UsageLimit? = nil,
        source: ClaudeUsageSource = .statusLine,
        capturedAt: Date
    ) {
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.fable = fable
        self.source = source
        self.capturedAt = capturedAt
    }

    private enum CodingKeys: String, CodingKey {
        case fiveHour
        case weekly
        case fable
        case source
        case capturedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(UsageLimit.self, forKey: .fiveHour)
        weekly = try container.decodeIfPresent(UsageLimit.self, forKey: .weekly)
        fable = try container.decodeIfPresent(UsageLimit.self, forKey: .fable)
        source = try container.decode(ClaudeUsageSource.self, forKey: .source)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
    }
}

public struct CodexUsageSnapshot: Codable, Hashable, Sendable {
    /// The single Codex limit exposed by the product. The app-server may
    /// return more than one raw window, but Dejavu intentionally publishes
    /// only the weekly limit.
    public let weekly: UsageLimit?
    public let resetCredits: Int?
    public let resetCreditsExpireAt: Date?
    public let planType: String?

    public init(
        weekly: UsageLimit?,
        resetCredits: Int?,
        resetCreditsExpireAt: Date?,
        planType: String?
    ) {
        self.weekly = weekly
        self.resetCredits = resetCredits
        self.resetCreditsExpireAt = resetCreditsExpireAt
        self.planType = planType
    }
}

public struct ApplicationState: Codable, Hashable, Sendable {
    public let combinedStatus: UsageStatus
    public let claudeStatus: UsageStatus
    public let claudeMessage: String
    public let claudeSnapshot: ClaudeUsageSnapshot?
    public let codexStatus: UsageStatus
    public let codexMessage: String
    public let codexSnapshot: CodexUsageSnapshot?
    public let updatedAt: Date?
    public let retryAt: Date?

    public init(
        combinedStatus: UsageStatus? = nil,
        claudeStatus: UsageStatus,
        claudeMessage: String = "",
        claudeSnapshot: ClaudeUsageSnapshot? = nil,
        codexStatus: UsageStatus,
        codexMessage: String = "",
        codexSnapshot: CodexUsageSnapshot? = nil,
        updatedAt: Date? = nil,
        retryAt: Date? = nil
    ) {
        self.combinedStatus = combinedStatus ?? .combined(claude: claudeStatus, codex: codexStatus)
        self.claudeStatus = claudeStatus
        self.claudeMessage = claudeMessage
        self.claudeSnapshot = claudeSnapshot
        self.codexStatus = codexStatus
        self.codexMessage = codexMessage
        self.codexSnapshot = codexSnapshot
        self.updatedAt = updatedAt
        self.retryAt = retryAt
    }

    public static let initial = ApplicationState(
        combinedStatus: .loading,
        claudeStatus: .loading,
        claudeMessage: "Checking Claude usage",
        codexStatus: .loading,
        codexMessage: "Checking Codex usage"
    )

    public func loading() -> Self {
        Self(
            combinedStatus: .loading,
            claudeStatus: .loading,
            claudeMessage: claudeSnapshot == nil ? "Checking Claude usage" : "Refreshing Claude usage",
            claudeSnapshot: claudeSnapshot,
            codexStatus: .loading,
            codexMessage: codexSnapshot == nil ? "Checking Codex usage" : "Refreshing Codex usage",
            codexSnapshot: codexSnapshot,
            updatedAt: updatedAt
        )
    }
}
