import Foundation

/// Matches the Windows updater's local wall-clock scheduling contract.
public enum HourlyUpdateSchedule {
    public static func nextCheckAt(
        after now: Date,
        calendar: Calendar = .current
    ) -> Date {
        if let startOfHour = calendar.dateInterval(of: .hour, for: now)?.start,
           let nextHour = calendar.date(byAdding: .hour, value: 1, to: startOfHour) {
            return nextHour
        }
        return now.addingTimeInterval(60 * 60)
    }
}

public enum AutomaticUpdatePolicy {
    public static func shouldNotify(
        availableVersion: String?,
        lastNotifiedVersion: String?
    ) -> Bool {
        guard let available = normalized(availableVersion) else { return false }
        return available.caseInsensitiveCompare(normalized(lastNotifiedVersion) ?? "") != .orderedSame
    }

    private static func normalized(_ version: String?) -> String? {
        guard let version else { return nil }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Keeps a discovered release until the feed definitively says it is current.
/// A transient failure or a new check must not withdraw a usable update.
public struct UpdateCheckState: Equatable, Sendable {
    public enum Presentation: Equatable, Sendable {
        case ready
        case checking
        case available(version: String)
        case current
        case failed
    }

    public enum Outcome: Equatable, Sendable {
        case completed
        case noUpdate
        case failed
    }

    public private(set) var availableVersion: String?
    public private(set) var presentation: Presentation = .ready

    public init() {}

    public mutating func beginCheck(manual: Bool) {
        if manual { presentation = .checking }
    }

    public mutating func foundUpdate(version: String) {
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else { return }
        availableVersion = version
        presentation = .available(version: version)
    }

    public mutating func finish(outcome: Outcome, manual: Bool) {
        if outcome == .noUpdate {
            availableVersion = nil
            presentation = manual ? .current : .ready
        } else if let availableVersion {
            presentation = .available(version: availableVersion)
        } else if outcome == .failed {
            presentation = manual ? .failed : .ready
        } else {
            presentation = manual ? .current : .ready
        }
    }
}
