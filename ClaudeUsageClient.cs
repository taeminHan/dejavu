using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;

namespace ClaudeUsageTray;

internal sealed record UsageLimit(double Percent, DateTimeOffset? ResetsAt);
internal sealed record UsageSnapshot(UsageLimit? FiveHour, UsageLimit? Weekly, UsageLimit? Fable);
internal sealed class ClaudeLoginRequiredException : Exception;
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

    public async Task<UsageSnapshot> GetUsageAsync(CancellationToken cancellationToken = default)
    {
        var credentialPath = ClaudeEnvironmentDetector.FindCredentialPath();
        if (credentialPath is null) throw new ClaudeLoginRequiredException();

        await using var credentialStream = new FileStream(
            credentialPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete,
            bufferSize: 4096, useAsync: true);
        using var credentialDocument = await JsonDocument.ParseAsync(credentialStream, cancellationToken: cancellationToken);
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
            throw new ClaudeLoginRequiredException();
        }

        using var request = new HttpRequestMessage(HttpMethod.Get, UsageUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenNode.GetString());
        request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
        request.Headers.UserAgent.ParseAdd("claude-code/2.1.215");

        using var response = await Http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            throw new ClaudeLoginRequiredException();
        if (response.StatusCode == HttpStatusCode.TooManyRequests)
        {
            var retryAfter = response.Headers.RetryAfter?.Delta ?? TimeSpan.FromMinutes(2);
            throw new ClaudeRateLimitException(retryAfter);
        }

        response.EnsureSuccessStatusCode();
        await using var responseStream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var usageDocument = await JsonDocument.ParseAsync(responseStream, cancellationToken: cancellationToken);
        var root = usageDocument.RootElement;

        return new UsageSnapshot(
            ReadArrayLimit(root, "session") ?? ReadLegacyLimit(root, "five_hour"),
            ReadArrayLimit(root, "weekly_all") ?? ReadLegacyLimit(root, "seven_day"),
            ReadScopedLimit(root, "Fable") ?? ReadLegacyLimit(root, "seven_day_fable") ??
                ReadLegacyLimit(root, "seven_day_opus") ?? ReadLegacyLimit(root, "seven_day_sonnet"));
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
