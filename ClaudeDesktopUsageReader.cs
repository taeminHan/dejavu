using System.Diagnostics;
using System.Text.Json;

namespace ClaudeUsageTray;

internal static class ClaudeDesktopUsageReader
{
    // Claude Desktop writes a sample about every 15 minutes while it runs, often a little later, and
    // occasionally skips one. The window covers a late or skipped write so a running Desktop does not
    // flip between available and stale at every write boundary.
    internal static readonly TimeSpan MaximumSampleAge = TimeSpan.FromMinutes(40);
    private static readonly TimeSpan MaximumFutureSkew = TimeSpan.FromMinutes(2);
    private const long MaximumHistoryBytes = 16 * 1024 * 1024;
    private const string HistoryFileName = "plan-usage-history.json";
    private const string PackageFamily = "Claude_pzs8sxrjxfjjc";
    private static readonly HistoryReader History = new(DataDirectories(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData)));

    internal static string[] DataDirectories(string roaming, string local)
    {
        var directories = new List<string>();
        if (Path.IsPathFullyQualified(local))
        {
            directories.Add(Path.Combine(local, "Claude-Data", PackageFamily.ToLowerInvariant()));
            directories.Add(Path.Combine(local, "Packages", PackageFamily, "LocalCache", "Roaming", "Claude"));
        }
        if (Path.IsPathFullyQualified(roaming)) directories.Add(Path.Combine(roaming, "Claude"));
        return [.. directories];
    }

    internal static bool IsInstalled => History.ActiveDirectory is not null;

    internal static bool HasRecentUsage() => TryReadRecent(out _);
    internal static bool TryReadRecent(out UsageSnapshot snapshot) => History.TryReadRecent(out snapshot);

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

    internal sealed class HistoryReader(string[] directories)
    {
        private readonly object _cacheLock = new();
        private HistoryFingerprint? _cachedFingerprint;
        private UsageSnapshot? _cachedSnapshot;
        internal string? ActiveDirectory => directories.FirstOrDefault(Directory.Exists);

        internal bool TryReadRecent(out UsageSnapshot snapshot)
        {
            lock (_cacheLock)
            {
                snapshot = null!;
                // Prefer the current data directory even before it produces a sample. A leftover
                // file from before an app migration can belong to a different login.
                var directory = ActiveDirectory;
                var path = directory is null ? null : Path.Combine(directory, HistoryFileName);
                if (path is null || !File.Exists(path))
                {
                    _cachedFingerprint = null;
                    _cachedSnapshot = null;
                    return false;
                }
                try
                {
                    var file = new FileInfo(path);
                    var fingerprint = new HistoryFingerprint(path, file.LastWriteTimeUtc.Ticks, file.Length);
                    if (_cachedFingerprint == fingerprint) return TryUseCachedSnapshot(path, out snapshot);
                    if (file.Length is <= 0 or > MaximumHistoryBytes) return TryUseCachedSnapshot(path, out snapshot);

                    var payload = ReadHistorySnapshot(path);
                    if (!TryParse(payload, out var parsed)) return TryUseCachedSnapshot(path, out snapshot);

                    _cachedFingerprint = fingerprint;
                    _cachedSnapshot = parsed;
                    snapshot = parsed;
                    return true;
                }
                catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException)
                {
                    return TryUseCachedSnapshot(path, out snapshot);
                }
            }
        }

        private bool TryUseCachedSnapshot(string path, out UsageSnapshot snapshot)
        {
            if (_cachedFingerprint?.Path == path &&
                _cachedSnapshot?.CapturedAt is { } capturedAt && IsRecent(capturedAt))
            {
                snapshot = _cachedSnapshot;
                return true;
            }

            snapshot = null!;
            return false;
        }
    }

    private static byte[] ReadHistorySnapshot(string path)
    {
        // Close Claude's file before JSON parsing. This keeps the shared read handle
        // alive only for the small copy and avoids interfering with a replace/write.
        using var stream = new FileStream(
            path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete,
            bufferSize: 4096, options: FileOptions.SequentialScan);
        var length = stream.Length;
        if (length is <= 0 or > MaximumHistoryBytes) throw new InvalidDataException();
        var payload = new byte[(int)length];
        stream.ReadExactly(payload);
        if (stream.ReadByte() != -1) throw new IOException();
        return payload;
    }

    private static bool TryParse(ReadOnlyMemory<byte> payload, out UsageSnapshot snapshot)
    {
        snapshot = null!;
        using var document = JsonDocument.Parse(payload);
        if (document.RootElement.ValueKind != JsonValueKind.Object ||
            !document.RootElement.TryGetProperty("samples", out var samples) ||
            samples.ValueKind != JsonValueKind.Array) return false;

        long latestTimestamp = long.MinValue;
        var now = DateTimeOffset.UtcNow;
        var earliest = (now - MaximumSampleAge).ToUnixTimeMilliseconds();
        var latest = (now + MaximumFutureSkew).ToUnixTimeMilliseconds();
        double? fiveHour = null;
        double? weekly = null;
        foreach (var sample in samples.EnumerateArray())
        {
            if (sample.ValueKind != JsonValueKind.Object ||
                !sample.TryGetProperty("t", out var timestampNode) || timestampNode.ValueKind != JsonValueKind.Number ||
                !timestampNode.TryGetInt64(out var timestamp) || timestamp <= latestTimestamp ||
                timestamp < earliest || timestamp > latest ||
                !sample.TryGetProperty("u", out var usage) || usage.ValueKind != JsonValueKind.Object) continue;

            latestTimestamp = timestamp;
            fiveHour = ReadPercent(usage, "fh");
            weekly = ReadPercent(usage, "sd");
        }

        if (latestTimestamp == long.MinValue || fiveHour is null && weekly is null) return false;
        var capturedAt = DateTimeOffset.FromUnixTimeMilliseconds(latestTimestamp);
        snapshot = new UsageSnapshot(
            ToLimit(fiveHour), ToLimit(weekly), Fable: null,
            Source: ClaudeUsageSource.ClaudeDesktop, CapturedAt: capturedAt);
        return true;
    }

    private static bool IsRecent(DateTimeOffset capturedAt)
    {
        var now = DateTimeOffset.UtcNow;
        return capturedAt >= now - MaximumSampleAge && capturedAt <= now + MaximumFutureSkew;
    }

    private static double? ReadPercent(JsonElement usage, string propertyName) =>
        usage.TryGetProperty(propertyName, out var node) && node.ValueKind == JsonValueKind.Number &&
        node.TryGetDouble(out var value) && double.IsFinite(value)
            ? Math.Clamp(value, 0, 100) : null;

    private static UsageLimit? ToLimit(double? percent) =>
        percent is null ? null : new UsageLimit(percent.Value, ResetsAt: null);

    private readonly record struct HistoryFingerprint(string Path, long LastWriteUtcTicks, long Length);
}
