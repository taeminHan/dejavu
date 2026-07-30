using System.Diagnostics;
using System.Text.Json;

namespace ClaudeUsageTray;

internal static class ClaudeDesktopUsageReader
{
    private static readonly TimeSpan MaximumSampleAge = TimeSpan.FromMinutes(15);
    private static readonly TimeSpan MaximumFutureSkew = TimeSpan.FromMinutes(2);

    private static string ClaudeDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Claude");

    internal static string HistoryPath => Path.Combine(ClaudeDirectory, "plan-usage-history.json");
    internal static bool IsInstalled => Directory.Exists(ClaudeDirectory);
    internal static bool HasHistoryFile => File.Exists(HistoryPath);

    internal static bool HasRecentUsage() => TryReadRecent(out _);

    internal static bool OpenDesktop()
    {
        try
        {
            Process.Start(new ProcessStartInfo("claude://claude.ai/new") { UseShellExecute = true });
            return true;
        }
        catch
        {
            return false;
        }
    }

    internal static bool TryReadRecent(out UsageSnapshot snapshot)
    {
        snapshot = null!;
        try
        {
            using var stream = new FileStream(
                HistoryPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            using var document = JsonDocument.Parse(stream);
            if (!document.RootElement.TryGetProperty("samples", out var samples) ||
                samples.ValueKind != JsonValueKind.Array) return false;

            long latestTimestamp = long.MinValue;
            double? fiveHour = null;
            double? weekly = null;
            foreach (var sample in samples.EnumerateArray())
            {
                if (!sample.TryGetProperty("t", out var timestampNode) ||
                    !timestampNode.TryGetInt64(out var timestamp) || timestamp <= latestTimestamp ||
                    !sample.TryGetProperty("u", out var usage) || usage.ValueKind != JsonValueKind.Object) continue;

                latestTimestamp = timestamp;
                fiveHour = ReadPercent(usage, "fh");
                weekly = ReadPercent(usage, "sd");
            }

            if (latestTimestamp == long.MinValue || fiveHour is null && weekly is null) return false;
            var capturedAt = DateTimeOffset.FromUnixTimeMilliseconds(latestTimestamp);
            var now = DateTimeOffset.UtcNow;
            if (capturedAt < now - MaximumSampleAge || capturedAt > now + MaximumFutureSkew) return false;

            snapshot = new UsageSnapshot(
                ToLimit(fiveHour), ToLimit(weekly), Fable: null,
                Source: ClaudeUsageSource.ClaudeDesktop, CapturedAt: capturedAt);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static double? ReadPercent(JsonElement usage, string propertyName) =>
        usage.TryGetProperty(propertyName, out var node) && node.TryGetDouble(out var value)
            ? Math.Clamp(value, 0, 100) : null;

    private static UsageLimit? ToLimit(double? percent) =>
        percent is null ? null : new UsageLimit(percent.Value, ResetsAt: null);
}
