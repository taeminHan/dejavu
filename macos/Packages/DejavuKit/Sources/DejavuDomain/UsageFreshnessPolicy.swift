import Foundation

public struct UsageFreshnessPolicy: Hashable, Sendable {
    public var maximumAgeWithoutReset: TimeInterval
    public var maximumFutureClockSkew: TimeInterval

    public init(
        maximumAgeWithoutReset: TimeInterval = 15 * 60,
        maximumFutureClockSkew: TimeInterval = 60
    ) {
        self.maximumAgeWithoutReset = max(0, maximumAgeWithoutReset)
        self.maximumFutureClockSkew = max(0, maximumFutureClockSkew)
    }

    /// Claude Desktop writes history samples only intermittently while it
    /// runs: often about every 15 minutes, but gaps of an hour or more occur
    /// on macOS. Its samples have no reset times, so the values of a sample
    /// expire after 40 minutes and then read `--%`; the Desktop provider keeps
    /// the Claude slot with that sample time instead of dropping it, so a
    /// running Desktop never disappears between samples. A sample more than
    /// 2 minutes ahead of the system clock is rejected. Both values match the
    /// Windows `ClaudeDesktopUsageReader`.
    public static let claudeDesktopHistory = UsageFreshnessPolicy(
        maximumAgeWithoutReset: 40 * 60,
        maximumFutureClockSkew: 2 * 60
    )

    /// Rejects a snapshot captured implausibly in the future and removes each
    /// limit independently after its reset or conservative no-reset TTL.
    public func freshClaudeSnapshot(
        from snapshot: ClaudeUsageSnapshot,
        now: Date = Date()
    ) -> ClaudeUsageSnapshot? {
        guard snapshot.capturedAt <= now.addingTimeInterval(maximumFutureClockSkew) else {
            return nil
        }

        let fiveHour = freshLimit(snapshot.fiveHour, capturedAt: snapshot.capturedAt, now: now)
        let weekly = freshLimit(snapshot.weekly, capturedAt: snapshot.capturedAt, now: now)
        let fable = freshLimit(snapshot.fable, capturedAt: snapshot.capturedAt, now: now)
        guard fiveHour != nil || weekly != nil || fable != nil else { return nil }

        return ClaudeUsageSnapshot(
            fiveHour: fiveHour,
            weekly: weekly,
            fable: fable,
            source: snapshot.source,
            capturedAt: snapshot.capturedAt
        )
    }

    public func freshLimit(_ limit: UsageLimit?, capturedAt: Date, now: Date = Date()) -> UsageLimit? {
        guard let limit else { return nil }
        if let resetsAt = limit.resetsAt {
            return resetsAt > now ? limit : nil
        }
        return now.timeIntervalSince(capturedAt) <= maximumAgeWithoutReset ? limit : nil
    }
}
