using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace ClaudeUsageTray;

internal sealed record UsageLimit(double Percent, DateTimeOffset? ResetsAt);
internal enum ClaudeUsageSource { ClaudeCode, ClaudeDesktop }
internal sealed record UsageSnapshot(
    UsageLimit? FiveHour,
    UsageLimit? Weekly,
    UsageLimit? Fable,
    ClaudeUsageSource Source = ClaudeUsageSource.ClaudeCode,
    DateTimeOffset? CapturedAt = null)
{
    // Not positional: the WidgetLayoutProbe reflects the 5-parameter constructor. Set only on a
    // carried snapshot whose Fable window has reset, so the value is unknown rather than absent.
    public bool FableExpired { get; init; }
}
internal sealed class ClaudeLoginRequiredException : Exception;
// The Claude Code access token expired but a refresh token is present: Claude Code renews it the
// next time it runs. Dejavu never refreshes or writes the token itself.
internal sealed class ClaudeTokenExpiredException : Exception;
// No Claude Code credential, and Claude Desktop history exists without a recent sample: Desktop is
// closed or idle, which is not a lost login.
internal sealed class ClaudeDesktopHistoryStaleException : Exception;
internal sealed class ClaudeRateLimitException(TimeSpan retryAfter) : Exception
{
    public TimeSpan RetryAfter { get; } = retryAfter;
}

internal sealed class ClaudeUsageClient
{
    // This path is used by Claude Code today, but it is not documented as a public
    // third-party integration contract. Keep the dependency isolated here.
    private const string UsageUrl = "https://api.anthropic.com/api/oauth/usage";
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(12) };

    public static bool HasCredentialFile() => ClaudeEnvironmentDetector.FindCredentialPath() is not null;
    public static bool HasLocalUsageSource() => HasCredentialFile() || ClaudeDesktopUsageReader.HasRecentUsage();

    public async Task<UsageSnapshot> GetUsageAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            return await GetClaudeCodeUsageAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is ClaudeLoginRequiredException or ClaudeTokenExpiredException)
        {
            if (ClaudeDesktopUsageReader.TryReadRecent(out var desktopSnapshot)) return desktopSnapshot;
            if (exception is ClaudeLoginRequiredException && !HasCredentialFile() &&
                ClaudeDesktopUsageReader.HasHistoryFile)
                throw new ClaudeDesktopHistoryStaleException();
            throw;
        }
    }

    private async Task<UsageSnapshot> GetClaudeCodeUsageAsync(CancellationToken cancellationToken)
    {
        var credentialPath = ClaudeEnvironmentDetector.FindCredentialPath();
        if (credentialPath is null) throw new ClaudeLoginRequiredException();

        byte[] credentialPayload;
        await using (var credentialStream = new FileStream(
                         credentialPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete,
                         bufferSize: 4096, useAsync: true))
        {
            using var memory = new MemoryStream();
            await credentialStream.CopyToAsync(memory, cancellationToken);
            credentialPayload = memory.ToArray();
        }

        // Do not hold Claude's credential file open while parsing or making the network request.
        using var credentialDocument = JsonDocument.Parse(credentialPayload);
        if (!credentialDocument.RootElement.TryGetProperty("claudeAiOauth", out var oauth) ||
            !oauth.TryGetProperty("accessToken", out var tokenNode) ||
            string.IsNullOrWhiteSpace(tokenNode.GetString()))
        {
            throw new ClaudeLoginRequiredException();
        }

        if (oauth.TryGetProperty("expiresAt", out var expiresNode) &&
            expiresNode.TryGetInt64(out var expiresAt) &&
            DateTimeOffset.FromUnixTimeMilliseconds(expiresAt) <= DateTimeOffset.UtcNow.AddSeconds(15))
        {
            // Only the presence of a refresh token is checked; its value is never used or kept.
            throw HasUsableRefreshToken(oauth) ? new ClaudeTokenExpiredException() : new ClaudeLoginRequiredException();
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, UsageUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenNode.GetString());
        request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
        request.Headers.UserAgent.ParseAdd("claude-code/2.1.215");

        // Buffer the small body inside SendAsync so the 12 s HttpClient timeout also covers it; a body
        // that stalls after the headers would otherwise hold the refresh gate indefinitely.
        using var response = await Http.SendAsync(request, cancellationToken);
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            throw new ClaudeLoginRequiredException();
        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            // Retry-After is either a delay or an HTTP date; the controller clamps the result.
            var retryHeader = response.Headers.RetryAfter;
            var retryAfter = retryHeader?.Delta ??
                             (retryHeader?.Date is DateTimeOffset retryDate
                                 ? retryDate - DateTimeOffset.UtcNow : (TimeSpan?)null) ??
                             TimeSpan.FromMinutes(2);
            throw new ClaudeRateLimitException(retryAfter);
        }

        response.EnsureSuccessStatusCode();
        await using var responseStream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var usageDocument = await JsonDocument.ParseAsync(responseStream, cancellationToken: cancellationToken);
        return ParseUsage(usageDocument.RootElement);
    }

    // Pure response parsing: regression tests do not need credentials or HTTP requests.
    internal static UsageSnapshot ParseUsage(JsonElement root)
    {
        return new UsageSnapshot(
            ReadArrayLimit(root, "session") ?? ReadLegacyLimit(root, "five_hour"),
            ReadArrayLimit(root, "weekly_all") ?? ReadLegacyLimit(root, "seven_day"),
            // Other model limits are not aliases for Fable. Missing Fable stays null.
            ReadScopedLimit(root, "Fable") ?? ReadLegacyLimit(root, "seven_day_fable"));
    }

    private static bool HasUsableRefreshToken(JsonElement oauth)
    {
        if (!oauth.TryGetProperty("refreshToken", out var refreshNode) || refreshNode.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(refreshNode.GetString())) return false;
        return !oauth.TryGetProperty("refreshTokenExpiresAt", out var refreshExpiresNode) ||
               refreshExpiresNode.ValueKind != JsonValueKind.Number ||
               !refreshExpiresNode.TryGetInt64(out var refreshExpiresAt) ||
               DateTimeOffset.FromUnixTimeMilliseconds(refreshExpiresAt) > DateTimeOffset.UtcNow;
    }

    private static UsageLimit? ReadArrayLimit(JsonElement root, string kind)
    {
        if (!root.TryGetProperty("limits", out var limits) || limits.ValueKind != JsonValueKind.Array) return null;
        foreach (var item in limits.EnumerateArray())
        {
            if (item.TryGetProperty("kind", out var kindNode) && kindNode.GetString() == kind)
                return ReadModernLimit(item);
        }
        return null;
    }

    private static UsageLimit? ReadScopedLimit(JsonElement root, string displayName)
    {
        if (!root.TryGetProperty("limits", out var limits) || limits.ValueKind != JsonValueKind.Array) return null;
        foreach (var item in limits.EnumerateArray())
        {
            if (!item.TryGetProperty("kind", out var kindNode) || kindNode.GetString() != "weekly_scoped" ||
                !item.TryGetProperty("scope", out var scope) ||
                !scope.TryGetProperty("model", out var model) ||
                !model.TryGetProperty("display_name", out var nameNode) ||
                !string.Equals(nameNode.GetString(), displayName, StringComparison.OrdinalIgnoreCase)) continue;
            return ReadModernLimit(item);
        }
        return null;
    }

    private static UsageLimit? ReadModernLimit(JsonElement item)
    {
        if (!item.TryGetProperty("percent", out var node) || !node.TryGetDouble(out var percent)) return null;
        return new UsageLimit(percent, ReadReset(item));
    }

    private static UsageLimit? ReadLegacyLimit(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var item) || item.ValueKind != JsonValueKind.Object ||
            !item.TryGetProperty("utilization", out var node) || !node.TryGetDouble(out var percent)) return null;
        return new UsageLimit(percent, ReadReset(item));
    }

    private static DateTimeOffset? ReadReset(JsonElement item) =>
        item.TryGetProperty("resets_at", out var node) && node.ValueKind == JsonValueKind.String &&
        DateTimeOffset.TryParse(node.GetString(), out var reset) ? reset : null;
}
