import Foundation
import DejavuDomain

public enum ClaudeStatusSnapshotParserError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
}

/// Extracts only the official Claude Code rate-limit fields from the status-line
/// stdin payload. The caller supplies the capture time so no session metadata is
/// retained in the returned value.
public struct ClaudeStatusLineParser: Sendable {
    public init() {}

    public func parse(_ data: Data, capturedAt: Date) throws -> ClaudeUsageSnapshot {
        let payload = try JSONDecoder().decode(StatusLinePayload.self, from: data)
        return ClaudeUsageSnapshot(
            fiveHour: payload.rateLimits?.fiveHour?.usageLimit,
            weekly: payload.rateLimits?.sevenDay?.usageLimit,
            source: .statusLine,
            capturedAt: capturedAt
        )
    }
}

/// Decodes the narrow, persisted output of the user-approved Claude status-line
/// bridge. It deliberately models only the two supported usage windows, schema
/// version, and capture time.
public struct ClaudeStatusSnapshotParser: Sendable {
    public init() {}

    public func parse(_ data: Data) throws -> ClaudeUsageSnapshot {
        let payload = try ProviderDecoding.decoder().decode(BridgePayload.self, from: data)
        guard payload.schemaVersion == 1 else {
            throw ClaudeStatusSnapshotParserError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        return ClaudeUsageSnapshot(
            fiveHour: payload.rateLimits?.fiveHour?.usageLimit,
            weekly: payload.rateLimits?.sevenDay?.usageLimit,
            source: .statusLine,
            capturedAt: payload.capturedAt
        )
    }
}

private struct StatusLinePayload: Decodable {
    let rateLimits: StatusLineRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

private struct StatusLineRateLimits: Decodable {
    let fiveHour: StatusLineWindow?
    let sevenDay: StatusLineWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct StatusLineWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    var usageLimit: UsageLimit {
        UsageLimit(
            percent: usedPercentage,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

private struct BridgePayload: Decodable {
    let schemaVersion: Int
    let capturedAt: Date
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case capturedAt = "captured_at"
        case rateLimits = "rate_limits"
    }
}

private struct RateLimits: Decodable {
    let fiveHour: ClaudeWindow?
    let sevenDay: ClaudeWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

private struct ClaudeWindow: Decodable {
    let usedPercentage: Double
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    var usageLimit: UsageLimit {
        UsageLimit(percent: usedPercentage, resetsAt: resetsAt)
    }
}
