using System.Diagnostics;
using System.Text.Json;

namespace ClaudeUsageTray;

internal sealed record CodexUsageSnapshot(
    UsageLimit? FiveHour,
    UsageLimit? Weekly,
    int? ResetCredits,
    DateTimeOffset? ResetCreditsExpireAt,
    string? PlanType);

internal sealed class CodexLoginRequiredException : Exception;
internal sealed class CodexCliUnavailableException : Exception;

internal sealed class CodexUsageClient
{
    public static string? FindExecutable()
    {
        var configured = Environment.GetEnvironmentVariable("CODEX_CLI_PATH");
        if (IsRunnable(configured)) return configured;

        var roots = new List<string>();
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (!string.IsNullOrWhiteSpace(appData)) roots.Add(Path.Combine(appData, "npm"));
        roots.Add(@"C:\nvm4w\nodejs");
        roots.AddRange((Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));

        foreach (var root in roots.Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var native = Path.Combine(root, "node_modules", "@openai", "codex", "node_modules", "@openai",
                "codex-win32-x64", "vendor", "x86_64-pc-windows-msvc", "bin", "codex.exe");
            if (File.Exists(native)) return native;

            var executable = Path.Combine(root, "codex.exe");
            if (File.Exists(executable) && !IsProtectedWindowsAppsPath(executable)) return executable;
        }

        return null;
    }

    public async Task<CodexUsageSnapshot> GetUsageAsync(CancellationToken cancellationToken = default)
    {
        var executable = FindExecutable() ?? throw new CodexCliUnavailableException();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));

        var startInfo = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("app-server");

        using var process = Process.Start(startInfo) ?? throw new CodexCliUnavailableException();
        try
        {
            await WriteAsync(process, new
            {
                method = "initialize",
                id = 0,
                @params = new { clientInfo = new { name = "dejavu", title = "dejavu", version = "0.9.0-rc.1" } }
            }, timeout.Token);
            await WriteAsync(process, new { method = "initialized", @params = new { } }, timeout.Token);
            await WriteAsync(process, new { method = "account/rateLimits/read", id = 1 }, timeout.Token);

            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync(timeout.Token);
                if (line is null) throw new CodexCliUnavailableException();
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (!root.TryGetProperty("id", out var id) || !id.TryGetInt32(out var requestId) || requestId != 1)
                    continue;
                if (root.TryGetProperty("error", out _)) throw new CodexLoginRequiredException();
                if (!root.TryGetProperty("result", out var result)) throw new CodexLoginRequiredException();
                return Parse(result);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new CodexCliUnavailableException();
        }
        finally
        {
            try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
        }
    }

    private static async Task WriteAsync(Process process, object message, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(message).AsMemory(), cancellationToken);
        await process.StandardInput.FlushAsync(cancellationToken);
    }

    private static CodexUsageSnapshot Parse(JsonElement result)
    {
        var windows = new List<(UsageLimit Limit, int Minutes)>();
        string? planType = null;

        if (result.TryGetProperty("rateLimitsByLimitId", out var byId) && byId.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in byId.EnumerateObject()) ReadBucket(property.Value, windows, ref planType);
        }
        else if (result.TryGetProperty("rateLimits", out var single) && single.ValueKind == JsonValueKind.Object)
        {
            ReadBucket(single, windows, ref planType);
        }

        var fiveHour = windows.Where(item => item.Minutes <= 360)
            .OrderByDescending(item => item.Minutes).Select(item => item.Limit).FirstOrDefault();
        var weekly = windows.Where(item => item.Minutes >= 7 * 24 * 60)
            .OrderByDescending(item => item.Minutes).Select(item => item.Limit).FirstOrDefault();

        int? resetCredits = null;
        DateTimeOffset? resetExpiry = null;
        if (result.TryGetProperty("rateLimitResetCredits", out var resets) && resets.ValueKind == JsonValueKind.Object)
        {
            if (resets.TryGetProperty("availableCount", out var count) && count.TryGetInt32(out var parsedCount))
                resetCredits = parsedCount;
            if (resets.TryGetProperty("credits", out var credits) && credits.ValueKind == JsonValueKind.Array)
            {
                foreach (var credit in credits.EnumerateArray())
                {
                    if (!credit.TryGetProperty("expiresAt", out var expiry) || !expiry.TryGetInt64(out var seconds)) continue;
                    var value = DateTimeOffset.FromUnixTimeSeconds(seconds);
                    if (resetExpiry is null || value < resetExpiry) resetExpiry = value;
                }
            }
        }

        return new CodexUsageSnapshot(fiveHour, weekly, resetCredits, resetExpiry, planType);
    }

    private static void ReadBucket(JsonElement bucket, List<(UsageLimit Limit, int Minutes)> windows, ref string? planType)
    {
        if (bucket.TryGetProperty("planType", out var plan) && plan.ValueKind == JsonValueKind.String)
            planType ??= plan.GetString();
        foreach (var propertyName in new[] { "primary", "secondary" })
        {
            if (!bucket.TryGetProperty(propertyName, out var window) || window.ValueKind != JsonValueKind.Object ||
                !window.TryGetProperty("usedPercent", out var used) || !used.TryGetDouble(out var percent) ||
                !window.TryGetProperty("windowDurationMins", out var duration) || !duration.TryGetInt32(out var minutes)) continue;
            DateTimeOffset? resetsAt = null;
            if (window.TryGetProperty("resetsAt", out var reset) && reset.TryGetInt64(out var seconds))
                resetsAt = DateTimeOffset.FromUnixTimeSeconds(seconds);
            windows.Add((new UsageLimit(percent, resetsAt), minutes));
        }
    }

    private static bool IsRunnable(string? path) => !string.IsNullOrWhiteSpace(path) && File.Exists(path) && !IsProtectedWindowsAppsPath(path);
    private static bool IsProtectedWindowsAppsPath(string path) =>
        path.Contains("\\Program Files\\WindowsApps\\", StringComparison.OrdinalIgnoreCase);
}
