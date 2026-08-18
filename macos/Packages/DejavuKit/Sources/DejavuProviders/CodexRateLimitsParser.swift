import Foundation
import DejavuDomain

public enum CodexRateLimitsParserError: Error, Sendable, Equatable {
    case responseError
    case missingResult
}

/// Decodes a single app-server `account/rateLimits/read` response. The exact
/// `rateLimitsByLimitId["codex"]` bucket wins; legacy fallback is allowed only
/// when the entire multi-bucket field is absent.
public struct CodexRateLimitsParser: Sendable {
    private static let weeklyDurationMinutes = 7 * 24 * 60

    public init() {}

    public func parseResponse(_ data: Data) throws -> CodexUsageSnapshot {
        let response = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        guard response.error == nil else {
            throw CodexRateLimitsParserError.responseError
        }
        guard let result = response.result else {
            throw CodexRateLimitsParserError.missingResult
        }
        return parse(result)
    }

    private func parse(_ result: RateLimitsResult) -> CodexUsageSnapshot {
        let bucket: RateLimitBucket?
        if result.hasRateLimitsByLimitID {
            bucket = result.rateLimitsByLimitID?["codex"]
        } else {
            bucket = result.rateLimits
        }

        let windows = [bucket?.primary, bucket?.secondary].compactMap { $0 }
        let weekly = selectWeekly(from: windows)?.usageLimit

        let resetCredits = result.rateLimitResetCredits?.availableCount.flatMap {
            $0 >= 0 ? $0 : nil
        }
        let resetCreditsExpireAt = result.rateLimitResetCredits?.credits?
            .compactMap(\.expiryDate)
            .min()

        return CodexUsageSnapshot(
            weekly: weekly,
            resetCredits: resetCredits,
            resetCreditsExpireAt: resetCreditsExpireAt,
            planType: bucket?.planType
        )
    }

    private func selectWeekly(from windows: [CodexWindow]) -> CodexWindow? {
        windows
            .filter { $0.windowDurationMins >= Self.weeklyDurationMinutes }
            .max { $0.windowDurationMins < $1.windowDurationMins }
    }
}

private struct ResponseEnvelope: Decodable {
    let result: RateLimitsResult?
    let error: ResponseError?
}

private struct ResponseError: Decodable {}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitBucket?
    let rateLimitsByLimitID: [String: RateLimitBucket]?
    let hasRateLimitsByLimitID: Bool
    let rateLimitResetCredits: ResetCredits?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitID = "rateLimitsByLimitId"
        case rateLimitResetCredits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try container.decodeIfPresent(RateLimitBucket.self, forKey: .rateLimits)
        rateLimitsByLimitID = try container.decodeIfPresent(
            [String: RateLimitBucket].self,
            forKey: .rateLimitsByLimitID
        )
        if container.contains(.rateLimitsByLimitID) {
            hasRateLimitsByLimitID = !(try container.decodeNil(forKey: .rateLimitsByLimitID))
        } else {
            hasRateLimitsByLimitID = false
        }
        rateLimitResetCredits = try container.decodeIfPresent(
            ResetCredits.self,
            forKey: .rateLimitResetCredits
        )
    }
}

private struct RateLimitBucket: Decodable {
    let planType: String?
    let primary: CodexWindow?
    let secondary: CodexWindow?
}

private struct CodexWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int
    let resetsAt: Int64?

    var usageLimit: UsageLimit {
        UsageLimit(
            percent: usedPercent,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private struct ResetCredits: Decodable {
    let availableCount: Int?
    let credits: [ResetCreditDetail]?
}

private struct ResetCreditDetail: Decodable {
    let expiresAt: Int64?

    var expiryDate: Date? {
        expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}
