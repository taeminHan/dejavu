namespace ClaudeUsageTray;

internal static class HourlyUpdateSchedule
{
    internal static DateTimeOffset NextCheckAt(DateTimeOffset now)
    {
        var currentHour = new DateTimeOffset(
            now.Year, now.Month, now.Day, now.Hour, 0, 0, now.Offset);
        return currentHour.AddHours(1);
    }
}

internal static class AutomaticUpdatePolicy
{
    internal static bool ShouldNotify(string? availableVersion, string? lastNotifiedVersion) =>
        !string.IsNullOrWhiteSpace(availableVersion) &&
        !string.Equals(availableVersion.Trim(), lastNotifiedVersion?.Trim(),
            StringComparison.OrdinalIgnoreCase);
}
