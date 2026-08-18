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
