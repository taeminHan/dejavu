using System.Text.Json;

namespace ClaudeUsageTray;

internal static class AppDiagnostics
{
    private static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "dejavu");

    public static void Write(ApplicationState state, System.Windows.Window widget)
    {
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            var payload = new
            {
                recordedAt = DateTimeOffset.Now,
                state = state.Status.ToString(),
                state.Message,
                state.UpdatedAt,
                state.RetryAt,
                fiveHour = state.Snapshot?.FiveHour?.Percent,
                weekly = state.Snapshot?.Weekly?.Percent,
                fable = state.Snapshot?.Fable?.Percent,
                claudeSource = state.Snapshot?.Source.ToString(),
                claudeCapturedAt = state.Snapshot?.CapturedAt,
                codexFiveHour = state.CodexSnapshot?.FiveHour?.Percent,
                codexWeekly = state.CodexSnapshot?.Weekly?.Percent,
                codexResetCredits = state.CodexSnapshot?.ResetCredits,
                widget = new { widget.IsVisible, widget.Left, widget.Top, widget.Width, widget.Height, widget.Opacity },
                credentialFilePresent = ClaudeUsageClient.HasCredentialFile(),
                desktopUsageAvailable = ClaudeDesktopUsageReader.HasRecentUsage()
            };
            File.WriteAllText(Path.Combine(DirectoryPath, "status.json"),
                JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch
        {
            // Diagnostics must never affect the always-on widget.
        }
    }

    public static void ClearCrashLog()
    {
        try
        {
            var path = Path.Combine(DirectoryPath, "crash.log");
            if (File.Exists(path)) File.Delete(path);
        }
        catch { }
    }
}
