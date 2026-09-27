using System.Diagnostics;
using System.Text.Json;

namespace ClaudeUsageTray;

internal sealed record CodexUsageSnapshot(
    UsageLimit? FiveHour,
    UsageLimit? Weekly,
    int? ResetCredits,
    DateTimeOffset? ResetCreditsExpireAt,
    string? PlanType)
{
    // Not positional: the WidgetLayoutProbe reflects the 5-parameter constructor. Set only on a
    // carried snapshot whose weekly window has reset, so the weekly value is unknown, not absent.
    public bool WeeklyExpired { get; init; }

    // The always-visible Codex value: weekly, or the 5-hour window only for accounts with no weekly window.
    public UsageLimit? DisplayLimit => Weekly ?? (WeeklyExpired ? null : FiveHour);
}

internal sealed class CodexLoginRequiredException(bool accountMissing = false) : Exception
{
    // -32600: no ChatGPT account at all, as opposed to a backend 401 for an account that exists.
    public bool AccountMissing { get; } = accountMissing;
}
// -32603 from account/rateLimits/read: upstream found ChatGPT auth, then the backend call failed.
internal sealed class CodexBackendFailedException : Exception;
internal sealed class CodexCliUnavailableException : Exception;
internal sealed class CodexLoginFailedException : Exception;
internal sealed class CodexTimeoutException : Exception;
internal sealed class CodexReadFailedException : Exception;

internal sealed class CodexUsageClient
{
    private const string WindowsAppDownloadUrl =
        "https://get.microsoft.com/installer/download/9PLM9XGG6VKS?cid=website_cta_psi";

    public static bool IsDesktopInstalled
    {
        get
        {
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "OpenAI", "Codex");
            return Directory.Exists(root);
        }
    }

    public static string? FindExecutable()
    {
        var configured = Environment.GetEnvironmentVariable("CODEX_CLI_PATH");
        if (IsRunnable(configured)) return configured;

        if (string.Equals(Environment.GetEnvironmentVariable("DEJAVU_CODEX_SOURCE"), "desktop",
                StringComparison.OrdinalIgnoreCase))
            return DesktopExecutableCandidates().FirstOrDefault(IsRunnable);

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

        foreach (var executable in DesktopExecutableCandidates())
        {
            if (IsRunnable(executable)) return executable;
        }

        return null;
    }

    public static bool IsDesktopBundledExecutable(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        var desktopRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenAI", "Codex", "bin") + Path.DirectorySeparatorChar;
        return Path.GetFullPath(path).StartsWith(Path.GetFullPath(desktopRoot), StringComparison.OrdinalIgnoreCase);
    }

    public static void OpenSetupPage() =>
        Process.Start(new ProcessStartInfo(WindowsAppDownloadUrl) { UseShellExecute = true });

    public async Task<CodexUsageSnapshot> GetUsageAsync(CancellationToken cancellationToken = default)
    {
        var executable = FindExecutable() ?? throw new CodexCliUnavailableException();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeout.Token);

        using var process = StartAppServer(executable);
        // A pending read on a redirected pipe may not observe the token on Windows. Only the 15 s
        // timeout kills Dejavu's own child to end the read. A forced refresh or shutdown lets the
        // pending read finish or time out first, so a child in the middle of an in-band OAuth
        // refresh can persist the rotated token before the kill in `finally`; at exit the child
        // drains in-flight requests on stdin EOF.
        using var killOnTimeout = timeout.Token.Register(() => KillChild(process));
        try
        {
            await InitializeAsync(process, linked.Token);
            await WriteAsync(process, new { method = "account/rateLimits/read", id = 1 }, linked.Token);

            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync(linked.Token);
                if (line is null)
                {
                    // The timeout kill closes stdout too; only an unprompted exit is a read failure.
                    if (linked.IsCancellationRequested) throw new OperationCanceledException(linked.Token);
                    throw new CodexReadFailedException();
                }

                JsonDocument document;
                try { document = JsonDocument.Parse(line); }
                catch (JsonException) { continue; }
                using (document)
                {
                    var root = document.RootElement;
                    // Skip notifications, server requests and other responses.
                    if (root.ValueKind != JsonValueKind.Object || root.TryGetProperty("method", out _) ||
                        !root.TryGetProperty("id", out var id) || id.ValueKind != JsonValueKind.Number ||
                        !id.TryGetInt32(out var requestId) || requestId != 1) continue;
                    // Never log or display the error message: it can carry backend or account details.
                    if (root.TryGetProperty("error", out var error)) throw ClassifyRateLimitError(error);
                    if (!root.TryGetProperty("result", out var result) || result.ValueKind != JsonValueKind.Object)
                        throw new CodexReadFailedException();
                    return Parse(result);
                }
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException &&
                                          cancellationToken.IsCancellationRequested)
        {
            // A forced refresh or shutdown cancelled the read; whatever the pipe reported, the
            // caller asked for cancellation and must see it.
            throw new OperationCanceledException(cancellationToken);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new CodexTimeoutException();
        }
        catch (IOException) when (timeout.IsCancellationRequested)
        {
            throw new CodexTimeoutException();
        }
        finally
        {
            KillChild(process);
        }
    }

    // `onBrowserOpened` receives the official login page once it has been opened, so a repeated login
    // request can reopen the same pending flow. The URL is never logged or displayed.
    public async Task LoginAsync(CancellationToken cancellationToken = default, Action<string>? onBrowserOpened = null)
    {
        var executable = FindExecutable() ?? throw new CodexCliUnavailableException();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromMinutes(5));
        using var process = StartAppServer(executable);
        // A pending read on a redirected pipe does not observe the token on Windows; killing
        // Dejavu's own child closes the pipe so the 5-minute timeout and shutdown end the read.
        using var killOnCancel = timeout.Token.Register(() => KillChild(process));
        var pageOpened = false;

        try
        {
            await InitializeAsync(process, timeout.Token);
            await WriteAsync(process, new
            {
                method = "account/login/start",
                id = 2,
                @params = new { type = "chatgpt", useHostedLoginSuccessPage = true, appBrand = "codex" }
            }, timeout.Token);

            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync(timeout.Token);
                if (line is null)
                {
                    // The kill above closes stdout too; only an unprompted exit is a login failure.
                    if (timeout.IsCancellationRequested) throw new OperationCanceledException(timeout.Token);
                    throw new CodexLoginFailedException();
                }
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (root.TryGetProperty("id", out var id) && id.TryGetInt32(out var requestId) && requestId == 2)
                {
                    if (root.TryGetProperty("error", out _)) throw new CodexLoginFailedException();
                    if (!root.TryGetProperty("result", out var result) ||
                        !result.TryGetProperty("authUrl", out var authUrlNode) ||
                        string.IsNullOrWhiteSpace(authUrlNode.GetString())) throw new CodexLoginFailedException();
                    var authUrl = authUrlNode.GetString()!;
                    Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true });
                    pageOpened = true;
                    onBrowserOpened?.Invoke(authUrl);
                    continue;
                }

                if (!pageOpened || !root.TryGetProperty("method", out var method) ||
                    method.GetString() != "account/login/completed" ||
                    !root.TryGetProperty("params", out var parameters)) continue;
                if (parameters.TryGetProperty("success", out var success) && success.ValueKind == JsonValueKind.True)
                    return;
                throw new CodexLoginFailedException();
            }
        }
        catch (Exception exception) when (exception is not OperationCanceledException &&
                                          cancellationToken.IsCancellationRequested)
        {
            // Shutdown killed the child; whatever the pipe reported, the caller must see cancellation.
            throw new OperationCanceledException(cancellationToken);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new CodexLoginFailedException();
        }
        catch (Exception exception) when (exception is IOException or JsonException && timeout.IsCancellationRequested)
        {
            // A broken pipe or a line cut off by the timeout kill.
            throw new CodexLoginFailedException();
        }
        finally
        {
            KillChild(process);
        }
    }

    private static async Task WriteAsync(Process process, object message, CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(JsonSerializer.Serialize(message).AsMemory(), cancellationToken);
        await process.StandardInput.FlushAsync(cancellationToken);
    }

    private static Process StartAppServer(string executable)
    {
        var startInfo = new ProcessStartInfo(executable)
        {
            UseShellExecute = false,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        startInfo.ArgumentList.Add("app-server");
        var process = Process.Start(startInfo) ?? throw new CodexCliUnavailableException();
        // Drain stderr so verbose app-server logging (for example RUST_LOG) cannot fill the pipe
        // and stall the child. Its content may include account details and is discarded, never logged.
        process.ErrorDataReceived += static (_, _) => { };
        process.BeginErrorReadLine();
        return process;
    }

    // Only ever called with the app-server child that Dejavu started itself.
    private static void KillChild(Process process)
    {
        try { if (!process.HasExited) process.Kill(entireProcessTree: true); } catch { }
    }

    private static async Task InitializeAsync(Process process, CancellationToken cancellationToken)
    {
        await WriteAsync(process, new
        {
            method = "initialize",
            id = 0,
            @params = new
            {
                clientInfo = new
                {
                    name = "dejavu", title = "dejavu", version = VelopackUpdateService.CurrentVersion
                }
            }
        }, cancellationToken);
        await WriteAsync(process, new { method = "initialized", @params = new { } }, cancellationToken);
    }

    private static IEnumerable<string> DesktopExecutableCandidates()
    {
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "OpenAI", "Codex", "bin");
        string[] versionDirectories;
        try { versionDirectories = Directory.GetDirectories(root); }
        catch { versionDirectories = []; }

        foreach (var directory in versionDirectories
                     .OrderByDescending(path => Directory.GetLastWriteTimeUtc(path)))
            yield return Path.Combine(directory, "codex.exe");
        yield return Path.Combine(root, "codex.exe");
    }

    // For this method the upstream handler returns -32600 only for missing or non-ChatGPT auth;
    // network/backend failures are -32603, which it returns only after it found ChatGPT auth, and
    // overload is -32001. The dispatcher also uses -32600 for requests it rejects before the
    // handler runs (unknown method or bad params from an older or newer CLI, not initialized,
    // draining, experimental-gated); logging in cannot fix those.
    // The message is matched only for these cases and is never logged or displayed.
    private static Exception ClassifyRateLimitError(JsonElement error)
    {
        if (error.ValueKind != JsonValueKind.Object) return new CodexReadFailedException();
        var code = error.TryGetProperty("code", out var codeNode) && codeNode.ValueKind == JsonValueKind.Number &&
                   codeNode.TryGetInt64(out var value) ? value : 0;
        var message = error.TryGetProperty("message", out var messageNode) && messageNode.ValueKind == JsonValueKind.String
            ? messageNode.GetString() ?? "" : "";
        if (code == -32600)
            return IsProtocolRejection(message)
                ? new CodexReadFailedException() : new CodexLoginRequiredException(accountMissing: true);
        if (code == -32603)
            return message.Contains("401 Unauthorized", StringComparison.OrdinalIgnoreCase)
                ? new CodexLoginRequiredException() : new CodexBackendFailedException();
        return new CodexReadFailedException();
    }

    private static bool IsProtocolRejection(string message) =>
        message.StartsWith("Invalid request", StringComparison.Ordinal) ||
        message.StartsWith("Not initialized", StringComparison.Ordinal) ||
        message.StartsWith("Already initialized", StringComparison.Ordinal) ||
        message.StartsWith("Server is draining", StringComparison.Ordinal) ||
        message.Contains("requires experimentalApi capability", StringComparison.Ordinal);

    private static CodexUsageSnapshot Parse(JsonElement result)
    {
        var windows = new List<(UsageLimit Limit, int Minutes)>();
        string? planType = null;

        // Read only the "codex" bucket. The multi-bucket map is a Rust HashMap upstream, so its
        // order changes per app-server process; `rateLimits` is upstream's single view of the same
        // bucket (or of the first bucket when none is named "codex").
        if (result.TryGetProperty("rateLimitsByLimitId", out var byId) && byId.ValueKind == JsonValueKind.Object &&
            byId.TryGetProperty("codex", out var codex) && codex.ValueKind == JsonValueKind.Object)
        {
            ReadBucket(codex, windows, ref planType);
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
            if (resets.TryGetProperty("availableCount", out var count) && IsNumber(count) &&
                count.TryGetInt32(out var parsedCount))
                resetCredits = parsedCount;
            if (resets.TryGetProperty("credits", out var credits) && credits.ValueKind == JsonValueKind.Array)
            {
                foreach (var credit in credits.EnumerateArray())
                {
                    // Upstream serializes a credit that never expires as "expiresAt": null.
                    if (credit.ValueKind != JsonValueKind.Object || !credit.TryGetProperty("expiresAt", out var expiry) ||
                        !IsNumber(expiry) || !expiry.TryGetInt64(out var seconds)) continue;
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
            // Optional window fields arrive as JSON null; TryGet* throws on a non-number element.
            if (!bucket.TryGetProperty(propertyName, out var window) || window.ValueKind != JsonValueKind.Object ||
                !window.TryGetProperty("usedPercent", out var used) || !IsNumber(used) ||
                !used.TryGetDouble(out var percent) ||
                !window.TryGetProperty("windowDurationMins", out var duration) || !IsNumber(duration) ||
                !duration.TryGetInt32(out var minutes)) continue;
            DateTimeOffset? resetsAt = null;
            if (window.TryGetProperty("resetsAt", out var reset) && IsNumber(reset) && reset.TryGetInt64(out var seconds))
                resetsAt = DateTimeOffset.FromUnixTimeSeconds(seconds);
            windows.Add((new UsageLimit(percent, resetsAt), minutes));
        }
    }

    private static bool IsNumber(JsonElement element) => element.ValueKind == JsonValueKind.Number;

    private static bool IsRunnable(string? path) => !string.IsNullOrWhiteSpace(path) && File.Exists(path) && !IsProtectedWindowsAppsPath(path);
    private static bool IsProtectedWindowsAppsPath(string path) =>
        path.Contains("\\Program Files\\WindowsApps\\", StringComparison.OrdinalIgnoreCase);
}
