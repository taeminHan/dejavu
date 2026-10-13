import Foundation

/// Monotonic deadlines prevent clock changes and settings edits from delaying
/// an already pending recovery. This policy never starts a provider itself.
public struct UsageRefreshSchedule: Sendable {
    public private(set) var deadline: ContinuousClock.Instant?
    public private(set) var transientFailures = 0

    public init() {}

    public mutating func completed(
        state: ApplicationState,
        interval: TimeInterval,
        wallNow: Date = Date(),
        now: ContinuousClock.Instant = .now
    ) {
        let transient = state.claudeStatus == .offline || state.codexStatus == .offline
            || (state.claudeStatus == .error && state.claudeIssue != .tokenRefreshPending)
            || (state.codexStatus == .error && state.codexIssue != .tokenRefreshPending)
        transientFailures = transient ? transientFailures + 1 : 0
        var delay = max(1, interval)
        if transientFailures == 1 { delay = min(delay, 10) }
        if transientFailures == 2 { delay = min(delay, 30) }
        if let retryAt = state.retryAt, retryAt > wallNow {
            delay = min(delay, max(1, retryAt.timeIntervalSince(wallNow) + 0.5))
        }
        deadline = now.advanced(by: .seconds(delay))
    }

    public mutating func bringForward(after seconds: TimeInterval, now: ContinuousClock.Instant = .now) {
        let candidate = now.advanced(by: .seconds(max(0, seconds)))
        if deadline == nil || candidate < deadline! { deadline = candidate }
    }

    public mutating func consume() { deadline = nil }
}
