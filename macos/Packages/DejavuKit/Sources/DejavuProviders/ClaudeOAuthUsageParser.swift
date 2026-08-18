import Foundation
import DejavuDomain

/// Parses the narrow usage response used by Claude Code's own usage screen.
///
/// This response is not a documented third-party integration contract. The
/// parser is intentionally separate from credential access and networking so
/// the macOS app can keep the feature disabled unless the user explicitly
/// enables the extended Fable connection.
public struct ClaudeOAuthUsageParser: Sendable {
    public init() {}

    public func parse(_ data: Data, capturedAt: Date) throws -> ClaudeUsageSnapshot {
        let payload = try ProviderDecoding.decoder().decode(Payload.self, from: data)
        return ClaudeUsageSnapshot(
            fiveHour: payload.limit(kind: "session") ?? payload.fiveHour?.usageLimit,
            weekly: payload.limit(kind: "weekly_all") ?? payload.sevenDay?.usageLimit,
            fable: payload.fableLimit ?? payload.sevenDayFable?.usageLimit,
            source: .oauthUsage,
            capturedAt: capturedAt
        )
    }
}

private struct Payload: Decodable {
    let limits: [ModernLimit]?
    let fiveHour: LegacyLimit?
    let sevenDay: LegacyLimit?
    let sevenDayFable: LegacyLimit?

    enum CodingKeys: String, CodingKey {
        case limits
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayFable = "seven_day_fable"
    }

    func limit(kind: String) -> UsageLimit? {
        limits?.first { $0.kind == kind }?.usageLimit
    }

    var fableLimit: UsageLimit? {
        limits?.first { limit in
            guard limit.kind == "weekly_scoped", let displayName = limit.modelDisplayName else {
                return false
            }
            let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.caseInsensitiveCompare("Fable") == .orderedSame
                || normalized.caseInsensitiveCompare("Fable 5") == .orderedSame
        }?.usageLimit
    }
}

private struct ModernLimit: Decodable {
    let kind: String
    let percent: Double?
    let resetsAt: Date?
    let scope: Scope?

    enum CodingKeys: String, CodingKey {
        case kind
        case percent
        case resetsAt = "resets_at"
        case scope
    }

    var usageLimit: UsageLimit? {
        percent.map { UsageLimit(percent: $0, resetsAt: resetsAt) }
    }

    var modelDisplayName: String? { scope?.model?.displayName }
}

private struct Scope: Decodable {
    let model: ScopedModel?
}

private struct ScopedModel: Decodable {
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
    }
}

private struct LegacyLimit: Decodable {
    let utilization: Double?
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var usageLimit: UsageLimit? {
        utilization.map { UsageLimit(percent: $0, resetsAt: resetsAt) }
    }
}
