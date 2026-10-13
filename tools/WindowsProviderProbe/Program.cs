using System.Diagnostics;
using System.Reflection;
using System.Text.Json;
using ClaudeUsageTray;

// A child of this executable substitutes for app-server. It exchanges synthetic JSON/markers only;
// it never discovers a CLI, reads real credentials/history/settings, logs in or makes network calls.
if (args is ["app-server"]) return await SyntheticAppServer.RunAsync();
return await new ProviderProbe().RunAsync();

internal sealed class ProviderProbe
{
    private int _checks;
    private readonly List<string> _failures = [];

    internal async Task<int> RunAsync()
    {
        ParseCodexCases();
        await RunCaseAsync("Claude credential fallback", CheckClaudeCredentialsAsync);
        await RunCaseAsync("Codex successful read", CheckSuccessfulReadAsync);
        await RunCaseAsync("Codex cancel before start", CheckCancelledBeforeStartAsync);
        await RunCaseAsync("Codex cancelled drain", () => CheckCancelledDrainAsync("drain"));
        await RunCaseAsync("Codex cancelled error drain", () => CheckCancelledDrainAsync("error"));
        await RunCaseAsync("legacy cancellation regression", CheckLegacyCancellationAsync);
        await RunCaseAsync("Codex 15-second timeout", CheckTimeoutAsync);
        Console.WriteLine($"Windows provider regression: {_checks} checked, {_failures.Count} failures");
        foreach (var failure in _failures) Console.Error.WriteLine("PROVIDER " + failure);
        return _failures.Count == 0 ? 0 : 1;
    }

    private async Task RunCaseAsync(string name, Func<Task> test)
    {
        try { await test(); }
        catch (Exception exception) { Check(false, name + " threw " + exception.GetType().Name); }
    }

    private void Check(bool condition, string name)
    {
        _checks++;
        if (!condition) _failures.Add(name);
    }

    private void ParseCodexCases()
    {
        const string legacy = "\"rateLimits\":{\"planType\":\"synthetic\",\"secondary\":{\"usedPercent\":88,\"windowDurationMins\":10080}}";
        var cases = new (string Name, string Fields, double? Weekly)[]
        {
            ("legacy absent map", legacy, 88),
            ("legacy null map", "\"rateLimitsByLimitId\":null," + legacy, 88),
            ("empty map authoritative", "\"rateLimitsByLimitId\":{}," + legacy, null),
            ("other bucket authoritative", "\"rateLimitsByLimitId\":{\"code-review\":{\"secondary\":{\"usedPercent\":88,\"windowDurationMins\":10080}}}," + legacy, null),
            ("malformed map authoritative", "\"rateLimitsByLimitId\":[]," + legacy, null),
            ("null codex bucket", "\"rateLimitsByLimitId\":{\"codex\":null}," + legacy, null),
            ("malformed codex bucket", "\"rateLimitsByLimitId\":{\"codex\":42}," + legacy, null),
            ("empty codex bucket", "\"rateLimitsByLimitId\":{\"codex\":{}}," + legacy, null),
            ("codex wins", "\"rateLimitsByLimitId\":{\"codex\":{\"secondary\":{\"usedPercent\":19,\"windowDurationMins\":10080}}}," + legacy, 19),
            ("null primary preserves weekly", "\"rateLimitsByLimitId\":{\"codex\":{\"primary\":null,\"secondary\":{\"usedPercent\":21,\"windowDurationMins\":10080,\"resetsAt\":null}}}", 21),
            ("no data remains unknown", "", null),
            ("null optional reset credits", "\"rateLimitsByLimitId\":{\"codex\":{}},\"rateLimitResetCredits\":{\"availableCount\":null,\"credits\":[{\"expiresAt\":null}]}", null)
        };
        foreach (var item in cases)
        {
            using var document = JsonDocument.Parse("{" + item.Fields + "}");
            var snapshot = CodexUsageClient.Parse(document.RootElement);
            Check(snapshot.Weekly?.Percent == item.Weekly, item.Name);
        }

        // Reproduce the former fallback condition independently. The same fixture above must no
        // longer display this unrelated 88% through the linked production parser.
        using var previous = JsonDocument.Parse("{\"rateLimitsByLimitId\":{\"code-review\":{}}," + legacy + "}");
        var root = previous.RootElement;
        var usedLegacy = !(root.TryGetProperty("rateLimitsByLimitId", out var map) &&
                           map.ValueKind == JsonValueKind.Object && map.TryGetProperty("codex", out var codex) &&
                           codex.ValueKind == JsonValueKind.Object) && root.TryGetProperty("rateLimits", out _);
        Check(usedLegacy, "former parser branch reproduced unrelated-bucket fallback");
    }

    private async Task CheckClaudeCredentialsAsync()
    {
        using var fixture = new ProbeFixture("credentials");
        var path = Path.Combine(fixture.DirectoryPath, "synthetic.credentials.json");
        var desktop = new UsageSnapshot(new UsageLimit(12, null), new UsageLimit(34, null), null,
            ClaudeUsageSource.ClaudeDesktop, DateTimeOffset.UtcNow);
        var malformed = new[]
        {
            "{", "null", "[]", "42", "\"not-an-object\"", "{}",
            "{\"claudeAiOauth\":null}", "{\"claudeAiOauth\":[]}",
            "{\"claudeAiOauth\":{}}", "{\"claudeAiOauth\":{\"accessToken\":null}}",
            "{\"claudeAiOauth\":{\"accessToken\":42}}", "{\"claudeAiOauth\":{\"accessToken\":\" \"}}",
            "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-only\",\"expiresAt\":null}}",
            "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-only\",\"expiresAt\":\"wrong-type\"}}",
            "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-only\",\"expiresAt\":9223372036854775807}}"
        };
        for (var index = 0; index < malformed.Length; index++)
        {
            await File.WriteAllTextAsync(path, malformed[index]);
            var client = new ClaudeUsageClient(() => path, () => desktop, () => true);
            Check(ReferenceEquals(await client.GetUsageAsync(), desktop), "malformed credential uses Desktop " + index);
            client = new ClaudeUsageClient(() => path, () => null, () => false);
            Check(await ThrowsAsync<ClaudeLoginRequiredException>(() => client.GetUsageAsync()),
                "malformed credential login classification " + index);
        }

        // The old unguarded credential parse throws JsonException rather than reaching fallback.
        Check(Throws<JsonException>(() => JsonDocument.Parse("{")), "former malformed-JSON exception reproduced");
        var missing = new ClaudeUsageClient(() => null, () => desktop, () => true);
        Check(ReferenceEquals(await missing.GetUsageAsync(), desktop), "missing credential keeps Desktop fallback");
        var stale = new ClaudeUsageClient(() => null, () => null, () => true);
        Check(await ThrowsAsync<ClaudeDesktopHistoryStaleException>(() => stale.GetUsageAsync()), "missing credential stale Desktop classification");
        var absent = new ClaudeUsageClient(() => null, () => null, () => false);
        Check(await ThrowsAsync<ClaudeLoginRequiredException>(() => absent.GetUsageAsync()), "no source login classification");

        await File.WriteAllTextAsync(path, "{\"claudeAiOauth\":{\"accessToken\":\"synthetic-only\",\"expiresAt\":1,\"refreshToken\":\"synthetic-only\"}}");
        var expired = new ClaudeUsageClient(() => path, () => null, () => false);
        Check(await ThrowsAsync<ClaudeTokenExpiredException>(() => expired.GetUsageAsync()), "expired token retains renewal classification");
        var expiredWithDesktop = new ClaudeUsageClient(() => path, () => desktop, () => true);
        Check(ReferenceEquals(await expiredWithDesktop.GetUsageAsync(), desktop), "expired token retains Desktop fallback");

        var inaccessible = new ClaudeUsageClient(() => Path.Combine(fixture.DirectoryPath, "missing.json"), () => desktop, () => true);
        Check(await ThrowsAsync<FileNotFoundException>(() => inaccessible.GetUsageAsync()), "I/O failure is not relabeled as malformed authentication");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        var sourceRead = false;
        var cancelledClient = new ClaudeUsageClient(() => { sourceRead = true; return path; }, () => desktop, () => true);
        Check(await ThrowsAsync<OperationCanceledException>(() => cancelledClient.GetUsageAsync(cancelled.Token)) && !sourceRead,
            "cancelled Claude read touches no source and never falls back");
        using var malformedUsage = JsonDocument.Parse("{\"seven_day_fable\":{\"utilization\":null}}");
        Check(Throws<InvalidOperationException>(() => ClaudeUsageClient.ParseUsage(malformedUsage.RootElement)),
            "malformed usage response is not relabeled as authentication");
    }

    private async Task CheckSuccessfulReadAsync()
    {
        using var fixture = new ProbeFixture("drain");
        var client = fixture.CreateClient();
        var pending = client.GetUsageAsync();
        await fixture.WaitForMarkerAsync("request-started");
        await fixture.ObserveChildAsync();
        fixture.Release();
        var snapshot = await pending.WaitAsync(TimeSpan.FromSeconds(10));
        Check(snapshot.Weekly?.Percent == 42, "synthetic app-server returns production-parsed weekly value");
        Check(File.Exists(fixture.Marker("completed")), "successful child completes synthetic write before response");
        Check(await fixture.ChildExitedAsync(), "successful read cleans up only its own child");
        Check(fixture.ArgumentWasAppServer, "production child argument remains app-server");
    }

    private async Task CheckCancelledBeforeStartAsync()
    {
        using var fixture = new ProbeFixture("success");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        var discoveryCount = 0;
        var client = fixture.CreateClient(() => { discoveryCount++; return ProbeFixture.ExecutablePath; });
        Check(await ThrowsAsync<OperationCanceledException>(() => client.GetUsageAsync(cancelled.Token)), "pre-cancelled read returns cancellation");
        Check(discoveryCount == 0 && !File.Exists(fixture.Marker("pid")), "pre-cancelled read discovers/starts no child");

        using var race = new CancellationTokenSource();
        client = fixture.CreateClient(() => { race.Cancel(); return ProbeFixture.ExecutablePath; });
        Check(await ThrowsAsync<OperationCanceledException>(() => client.GetUsageAsync(race.Token)) &&
              !File.Exists(fixture.Marker("pid")), "cancellation during discovery starts no child");
    }

    private async Task CheckCancelledDrainAsync(string mode)
    {
        using var fixture = new ProbeFixture(mode);
        using var caller = new CancellationTokenSource();
        var pending = fixture.CreateClient().GetUsageAsync(caller.Token);
        await fixture.WaitForMarkerAsync("request-started");
        await fixture.ObserveChildAsync();
        caller.Cancel();
        // The child cannot finish until released; cancellation must keep it alive and pending.
        await Task.Delay(200);
        Check(!pending.IsCompleted && !fixture.ChildHasExited, mode + " caller cancellation waits for request drain");
        fixture.Release();
        var cancelled = false;
        try { await pending.WaitAsync(TimeSpan.FromSeconds(10)); }
        catch (OperationCanceledException exception) { cancelled = exception.CancellationToken == caller.Token; }
        Check(cancelled, mode + " drained response still reports the original caller cancellation");
        Check(File.Exists(fixture.Marker("completed")), mode + " synthetic persistence completed before cleanup");
        Check(await fixture.ChildExitedAsync(), mode + " drained child is cleaned up");
    }

    private async Task CheckLegacyCancellationAsync()
    {
        using var fixture = new ProbeFixture("drain");
        using var caller = new CancellationTokenSource();
        // This is the former linked-token pipe/finally-kill pattern, not another provider client.
        var pending = ReadWithFormerCancellationPatternAsync(fixture, caller.Token);
        await fixture.WaitForMarkerAsync("request-started");
        await fixture.ObserveChildAsync();
        caller.Cancel();
        await Task.Delay(200);
        if (pending.IsCompleted)
        {
            Check(await ThrowsAsync<OperationCanceledException>(() => pending),
                "former linked pipe pattern exits on caller cancellation");
            Check(await fixture.ChildExitedAsync() && !File.Exists(fixture.Marker("completed")),
                "former cancellation pattern kills child before synthetic persistence");
            Console.WriteLine("Former linked-pipe cancellation: early-abort reproduced");
        }
        else
        {
            // Some Windows redirected-pipe implementations do not observe cancellation during a
            // pending synchronous read. Do not manufacture an old-build failure on that runtime.
            Check(!fixture.ChildHasExited, "former linked pipe ignores pending cancellation on this runtime");
            fixture.Release();
            try { await pending.WaitAsync(TimeSpan.FromSeconds(5)); }
            catch (OperationCanceledException) { }
            Check(await fixture.ChildExitedAsync() && File.Exists(fixture.Marker("completed")),
                "former non-cancellable pipe completes synthetic persistence");
            Console.WriteLine("Former linked-pipe cancellation: pending pipe did not observe caller cancellation");
        }
    }

    private static async Task ReadWithFormerCancellationPatternAsync(ProbeFixture fixture, CancellationToken caller)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(caller, timeout.Token);
        using var child = fixture.StartChild();
        try
        {
            await child.StandardInput.WriteLineAsync("{\"method\":\"account/rateLimits/read\",\"id\":1}".AsMemory(), linked.Token);
            await child.StandardInput.FlushAsync(linked.Token);
            await child.StandardOutput.ReadLineAsync(linked.Token);
        }
        finally { if (!child.HasExited) child.Kill(entireProcessTree: true); }
    }

    private async Task CheckTimeoutAsync()
    {
        using var fixture = new ProbeFixture("blocked");
        var started = Stopwatch.StartNew();
        var pending = fixture.CreateClient().GetUsageAsync();
        await fixture.WaitForMarkerAsync("request-started");
        await fixture.ObserveChildAsync();
        Check(await ThrowsAsync<CodexTimeoutException>(() => pending.WaitAsync(TimeSpan.FromSeconds(22))),
            "silent child becomes CodexTimeoutException");
        Check(started.Elapsed >= TimeSpan.FromSeconds(13) && started.Elapsed < TimeSpan.FromSeconds(22),
            "production 15-second bound is retained");
        Check(await fixture.ChildExitedAsync() && !File.Exists(fixture.Marker("completed")),
            "timeout kills only the silent synthetic child");
    }

    private static async Task<bool> ThrowsAsync<T>(Func<Task> action) where T : Exception
    {
        try { await action(); return false; }
        catch (T) { return true; }
    }

    private static bool Throws<T>(Action action) where T : Exception
    {
        try { action(); return false; }
        catch (T) { return true; }
    }
}

internal sealed class ProbeFixture : IDisposable
{
    private const string ModeVariable = "DEJAVU_PROVIDER_PROBE_MODE";
    private const string DirectoryVariable = "DEJAVU_PROVIDER_PROBE_DIRECTORY";
    private readonly string _mode;
    private Process? _child;
    internal string DirectoryPath { get; } = Directory.CreateTempSubdirectory("dejavu-provider-probe-").FullName;
    internal static string ExecutablePath => Environment.ProcessPath ?? throw new InvalidOperationException("Missing probe process path");
    internal bool ArgumentWasAppServer { get; private set; }
    internal bool ChildHasExited => _child?.HasExited ?? false;

    internal ProbeFixture(string mode) => _mode = mode;
    internal string Marker(string name) => Path.Combine(DirectoryPath, name);
    internal void Release() => File.WriteAllText(Marker("release"), "synthetic-release");

    internal CodexUsageClient CreateClient(Func<string?>? findExecutable = null) =>
        new(findExecutable ?? (() => ExecutablePath), ConfigureChild);

    private void ConfigureChild(ProcessStartInfo info)
    {
        ArgumentWasAppServer = info.ArgumentList is { Count: 1 } && info.ArgumentList[0] == "app-server";
        // Supports both apphost execution and an explicit `dotnet WindowsProviderProbe.dll` run.
        if (string.Equals(Path.GetFileNameWithoutExtension(ExecutablePath), "dotnet", StringComparison.OrdinalIgnoreCase))
        {
            info.ArgumentList.Clear();
            info.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
            info.ArgumentList.Add("app-server");
        }
        info.Environment[ModeVariable] = _mode;
        info.Environment[DirectoryVariable] = DirectoryPath;
    }

    internal Process StartChild()
    {
        var info = new ProcessStartInfo(ExecutablePath)
        {
            UseShellExecute = false, RedirectStandardInput = true, RedirectStandardOutput = true,
            RedirectStandardError = true, CreateNoWindow = true
        };
        info.ArgumentList.Add("app-server");
        ConfigureChild(info);
        return Process.Start(info) ?? throw new InvalidOperationException("Synthetic child failed to start");
    }

    internal async Task ObserveChildAsync()
    {
        await WaitForMarkerAsync("pid");
        _child ??= Process.GetProcessById(int.Parse(await File.ReadAllTextAsync(Marker("pid"))));
    }

    internal async Task WaitForMarkerAsync(string name)
    {
        var elapsed = Stopwatch.StartNew();
        while (!File.Exists(Marker(name)))
        {
            if (elapsed.Elapsed > TimeSpan.FromSeconds(8)) throw new TimeoutException("Synthetic marker missing");
            await Task.Delay(20);
        }
    }

    internal async Task<bool> ChildExitedAsync()
    {
        if (_child is null) throw new InvalidOperationException("Synthetic child not observed");
        try { await _child.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(5)); return true; }
        catch (TimeoutException) { return false; }
    }

    public void Dispose()
    {
        // This handle is obtained only from the PID written by our own executable in this unique
        // temporary directory. Never enumerate, target or stop a real provider application.
        try { if (_child is { HasExited: false }) { _child.Kill(entireProcessTree: true); _child.WaitForExit(5000); } }
        catch (InvalidOperationException) { }
        _child?.Dispose();
        Directory.Delete(DirectoryPath, recursive: true);
    }

    internal static (string Mode, string Directory) ReadChildConfiguration()
    {
        var mode = Environment.GetEnvironmentVariable(ModeVariable);
        var directory = Environment.GetEnvironmentVariable(DirectoryVariable);
        if (string.IsNullOrWhiteSpace(mode) || string.IsNullOrWhiteSpace(directory) ||
            !Path.GetFileName(directory).StartsWith("dejavu-provider-probe-", StringComparison.Ordinal) ||
            !Directory.Exists(directory)) throw new InvalidOperationException("Synthetic child configuration missing");
        return (mode, directory);
    }
}

internal static class SyntheticAppServer
{
    internal async static Task<int> RunAsync()
    {
        var (mode, directory) = ProbeFixture.ReadChildConfiguration();
        await File.WriteAllTextAsync(Path.Combine(directory, "pid"), Environment.ProcessId.ToString());
        while (await Console.In.ReadLineAsync() is { } line)
        {
            using var document = JsonDocument.Parse(line);
            if (!document.RootElement.TryGetProperty("method", out var method) ||
                method.GetString() != "account/rateLimits/read") continue;
            await File.WriteAllTextAsync(Path.Combine(directory, "request-started"), "synthetic-request");
            if (mode == "blocked") await Task.Delay(Timeout.Infinite);
            if (mode is "drain" or "error")
                while (!File.Exists(Path.Combine(directory, "release"))) await Task.Delay(20);
            await File.WriteAllTextAsync(Path.Combine(directory, "completed"), "synthetic-write-completed");
            if (mode == "error")
                await Console.Out.WriteLineAsync("{\"id\":1,\"error\":{\"code\":-32603,\"message\":\"synthetic failure\"}}");
            else
            {
                // Non-response records must not disrupt the usage read.
                await Console.Out.WriteLineAsync("synthetic non-json output");
                await Console.Out.WriteLineAsync("[]");
                await Console.Out.WriteLineAsync("{\"method\":\"synthetic/request\",\"id\":1}");
                await Console.Out.WriteLineAsync("{\"id\":\"unrelated\"}");
                await Console.Out.WriteLineAsync("{\"id\":1,\"result\":{\"rateLimitsByLimitId\":{\"codex\":{\"secondary\":{\"usedPercent\":42,\"windowDurationMins\":10080}}}}}");
            }
            await Console.Out.FlushAsync();
        }
        return 0;
    }
}
