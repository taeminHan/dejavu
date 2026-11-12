using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

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
    private const int MaximumCredentialBytes = 256 * 1024;
    private static readonly HttpClient Http = new(new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
    {
        Timeout = TimeSpan.FromSeconds(12),
        MaxResponseContentBufferSize = 1024 * 1024
    };
    private static readonly Regex VersionedFable = new(@"\AFable [0-9]+(?:\.[0-9]+)*\z",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);
    private readonly Func<string?> _findCredentialPath;
    private readonly Func<UsageSnapshot?> _readDesktopSnapshot;
    private readonly Func<bool> _isDesktopInstalled;
    private readonly HttpClient _http;

    public ClaudeUsageClient() : this(
        ClaudeEnvironmentDetector.FindCredentialPath,
        static () => ClaudeDesktopUsageReader.TryReadRecent(out var snapshot) ? snapshot : null,
        static () => ClaudeDesktopUsageReader.IsInstalled) { }

    // Internal seams keep synthetic regression checks away from the user's credential/history paths.
    internal ClaudeUsageClient(Func<string?> findCredentialPath, Func<UsageSnapshot?> readDesktopSnapshot,
        Func<bool> isDesktopInstalled, HttpClient? http = null)
    {
        _findCredentialPath = findCredentialPath;
        _readDesktopSnapshot = readDesktopSnapshot;
        _isDesktopInstalled = isDesktopInstalled;
        _http = http ?? Http;
    }

    public static bool HasCredentialFile() => ClaudeEnvironmentDetector.FindCredentialPath() is not null;
    public static bool HasLocalUsageSource() => HasCredentialFile() || ClaudeDesktopUsageReader.HasRecentUsage();

    public async Task<UsageSnapshot> GetUsageAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            return await GetClaudeCodeUsageAsync(cancellationToken);
        }
        catch (Exception exception) when (exception is ClaudeLoginRequiredException or ClaudeTokenExpiredException
            or ClaudeCredentialReadException or HttpRequestException { StatusCode: HttpStatusCode.Forbidden })
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_readDesktopSnapshot() is { } desktopSnapshot) return desktopSnapshot;
            if (exception is ClaudeLoginRequiredException && _findCredentialPath() is null &&
                _isDesktopInstalled())
                throw new ClaudeDesktopHistoryStaleException();
            throw;
        }
    }

    private async Task<UsageSnapshot> GetClaudeCodeUsageAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var credentialPath = _findCredentialPath();
        if (credentialPath is null) throw new ClaudeLoginRequiredException();

        // Do not hold Claude's credential file open while parsing or making the network request.
        var credentialFingerprint = CredentialFingerprint(credentialPath);
        var credentialPayload = await ReadCredentialAsync(credentialPath, cancellationToken);
        string accessToken;
        try { accessToken = ParseCredential(credentialPayload.AsMemory(0, credentialPayload.Length - 1)); }
        finally { CryptographicOperations.ZeroMemory(credentialPayload); }
        cancellationToken.ThrowIfCancellationRequested();

        using var request = new HttpRequestMessage(HttpMethod.Get, UsageUrl);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
        request.Headers.TryAddWithoutValidation("anthropic-beta", "oauth-2025-04-20");
        request.Headers.UserAgent.ParseAdd("claude-code/2.1.215");

        // Buffer the small body inside SendAsync so the 12 s HttpClient timeout also covers it; a body
        // that stalls after the headers would otherwise hold the refresh gate indefinitely.
        using var response = await _http.SendAsync(request, cancellationToken);
        if (response.StatusCode == HttpStatusCode.Unauthorized)
        {
            // Claude can rotate its token while the usage request is in flight.
            if (CredentialFingerprint(_findCredentialPath()) != credentialFingerprint)
                throw new ClaudeCredentialReadException();
            throw new ClaudeLoginRequiredException();
        }
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

    private static async Task<byte[]> ReadCredentialAsync(string path, CancellationToken cancellationToken)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete,
            bufferSize: 1, useAsync: true);
        var length = stream.Length;
        if (length is <= 0 or > MaximumCredentialBytes) throw new ClaudeCredentialReadException();
        var payload = new byte[(int)length + 1];
        try
        {
            // Leave one extra byte to detect growth; never allocate based on later writes.
            var read = await stream.ReadAtLeastAsync(payload.AsMemory(), payload.Length, false, cancellationToken);
            if (read != length) throw new ClaudeCredentialReadException();
            return payload;
        }
        catch
        {
            CryptographicOperations.ZeroMemory(payload);
            throw;
        }
    }

    private static (string Path, long Length, DateTime WriteUtc)? CredentialFingerprint(string? path)
    {
        if (path is null) return null;
        var file = new FileInfo(path);
        return file.Exists ? (path, file.Length, file.LastWriteTimeUtc) : null;
    }

    private static string ParseCredential(ReadOnlyMemory<byte> payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);
            if (document.RootElement.ValueKind != JsonValueKind.Object ||
                !document.RootElement.TryGetProperty("claudeAiOauth", out var oauth) ||
                oauth.ValueKind != JsonValueKind.Object ||
                !oauth.TryGetProperty("accessToken", out var token) || token.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(token.GetString())) throw new ClaudeLoginRequiredException();

            if (oauth.TryGetProperty("expiresAt", out var expires))
            {
                if (expires.ValueKind != JsonValueKind.Number || !expires.TryGetInt64(out var milliseconds))
                    throw new ClaudeLoginRequiredException();
                if (DateTimeOffset.FromUnixTimeMilliseconds(milliseconds) <= DateTimeOffset.UtcNow.AddSeconds(15))
                    throw HasUsableRefreshToken(oauth)
                        ? new ClaudeTokenExpiredException() : new ClaudeLoginRequiredException();
            }

            return token.GetString()!;
        }
        catch (JsonException)
        {
            // A partially written credential file is a transient read error, not a lost login.
            throw new ClaudeCredentialReadException();
        }
        catch (ArgumentOutOfRangeException)
        {
            throw new ClaudeLoginRequiredException();
        }
    }

    // Pure response parsing: regression tests do not need credentials or HTTP requests.
    internal static UsageSnapshot ParseUsage(JsonElement root)
    {
        return new UsageSnapshot(
            ReadArrayLimit(root, "session") ?? ReadLegacyLimit(root, "five_hour"),
            ReadArrayLimit(root, "weekly_all") ?? ReadLegacyLimit(root, "seven_day"),
            // Other model limits are not aliases for Fable. Missing Fable stays null.
            ReadScopedFable(root) ?? ReadLegacyLimit(root, "seven_day_fable"));
    }

    private static bool HasUsableRefreshToken(JsonElement oauth)
    {
        if (!oauth.TryGetProperty("refreshToken", out var refreshNode) || refreshNode.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(refreshNode.GetString())) return false;
        return !oauth.TryGetProperty("refreshTokenExpiresAt", out var refreshExpiresNode) ||
               refreshExpiresNode.ValueKind == JsonValueKind.Null ||
               refreshExpiresNode.ValueKind == JsonValueKind.Number &&
               refreshExpiresNode.TryGetInt64(out var refreshExpiresAt) &&
               DateTimeOffset.FromUnixTimeMilliseconds(refreshExpiresAt) > DateTimeOffset.UtcNow;
    }

    private static UsageLimit? ReadArrayLimit(JsonElement root, string kind)
    {
        if (!root.TryGetProperty("limits", out var limits) || limits.ValueKind != JsonValueKind.Array) return null;
        foreach (var item in limits.EnumerateArray())
        {
            if (item.ValueKind == JsonValueKind.Object && item.TryGetProperty("kind", out var kindNode) &&
                kindNode.ValueKind == JsonValueKind.String && kindNode.GetString() == kind)
                return ReadModernLimit(item);
        }
        return null;
    }

    private static UsageLimit? ReadScopedFable(JsonElement root)
    {
        if (!root.TryGetProperty("limits", out var limits) || limits.ValueKind != JsonValueKind.Array) return null;
        JsonElement versioned = default;
        var ambiguous = false;
        foreach (var item in limits.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object ||
                !item.TryGetProperty("kind", out var kindNode) || kindNode.ValueKind != JsonValueKind.String ||
                kindNode.GetString() != "weekly_scoped" ||
                !item.TryGetProperty("scope", out var scope) || scope.ValueKind != JsonValueKind.Object ||
                !scope.TryGetProperty("model", out var model) || model.ValueKind != JsonValueKind.Object ||
                !model.TryGetProperty("display_name", out var nameNode) || nameNode.ValueKind != JsonValueKind.String)
                continue;
            var name = nameNode.GetString()!;
            if (name.Equals("Fable", StringComparison.OrdinalIgnoreCase)) return ReadModernLimit(item);
            if (!VersionedFable.IsMatch(name)) continue;
            if (versioned.ValueKind != JsonValueKind.Undefined) ambiguous = true;
            versioned = item;
        }
        return !ambiguous && versioned.ValueKind == JsonValueKind.Object ? ReadModernLimit(versioned) : null;
    }

    private static UsageLimit? ReadModernLimit(JsonElement item) => ReadLimit(item, "percent");

    private static UsageLimit? ReadLegacyLimit(JsonElement root, string name)
    {
        return root.TryGetProperty(name, out var item) && item.ValueKind == JsonValueKind.Object
            ? ReadLimit(item, "utilization") : null;
    }

    private static UsageLimit? ReadLimit(JsonElement item, string field)
    {
        if (!item.TryGetProperty(field, out var node) || node.ValueKind == JsonValueKind.Null) return null;
        if (node.ValueKind != JsonValueKind.Number || !node.TryGetDouble(out var percent) || !double.IsFinite(percent))
            throw new InvalidOperationException("Claude usage percentage has an invalid format.");
        return new UsageLimit(Math.Clamp(percent, 0, 100), ReadReset(item));
    }

    private static DateTimeOffset? ReadReset(JsonElement item) =>
        item.TryGetProperty("resets_at", out var node) && node.ValueKind == JsonValueKind.String &&
        DateTimeOffset.TryParse(node.GetString(), out var reset) ? reset : null;
}

internal sealed class ClaudeCredentialReadException : IOException;
