using System.Text.Json;

namespace ClaudeUsageTray;

internal static class AppDiagnostics
{
    private static string DirectoryPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "dejavu");

    public static void Write(ApplicationState state, UsageWidgetWindow widget, double widgetBackgroundOpacity,
        WidgetPlacement? placement = null, TaskbarTrackerState? taskbar = null, int taskbarRediscoveryCount = 0)
    {
        string? temporary = null;
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            // Taskbar diagnostics are Dejavu's own geometry and state only; never record the
            // titles or classes of other processes' windows.
            var taskbarPayload = taskbar is TaskbarTrackerState tracker
                ? new
                {
                    status = tracker.Status.ToString(),
                    reason = tracker.Reason,
                    bandLeftPixels = tracker.Dock?.BandLeftPixels,
                    bandTopPixels = tracker.Dock?.BandTopPixels,
                    bandRightPixels = tracker.Dock?.BandRightPixels,
                    bandBottomPixels = tracker.Dock?.BandBottomPixels,
                    anchorRightPixels = tracker.Dock?.AnchorRightPixels,
                    taskbarTopmost = tracker.TaskbarTopmost,
                    autoHide = tracker.AutoHide,
                    lightTaskbar = tracker.Dock?.LightTaskbar,
                    highContrast = tracker.Dock?.HighContrast,
                    rediscoveryCount = taskbarRediscoveryCount
                }
                : null;
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
                placement = placement?.ToString(),
                widget = new
                {
                    widget.IsVisible, widget.Left, widget.Top, widget.Width, widget.Height,
                    managedTopmost = widget.Topmost,
                    nativeTopmost = widget.NativeTopmost,
                    topmostRepairCount = widget.TopmostRepairCount,
                    lastTopmostRepairAt = widget.LastTopmostRepairAt,
                    lastTopmostRepairReason = widget.LastTopmostRepairReason,
                    lastTopmostRepairError = widget.LastTopmostRepairError,
                    taskbarDocked = widget.IsTaskbarDocked,
                    taskbarRaiseCount = widget.TaskbarRaiseCount,
                    lastTaskbarRaiseAt = widget.LastTaskbarRaiseAt,
                    lastTaskbarRaiseReason = widget.LastTaskbarRaiseReason,
                    lastTaskbarRaiseError = widget.LastTaskbarRaiseError,
                    windowOpacity = widget.Opacity,
                    backgroundOpacity = widgetBackgroundOpacity
                },
                taskbar = taskbarPayload,
                credentialFilePresent = ClaudeUsageClient.HasCredentialFile(),
                desktopUsageAvailable = ClaudeDesktopUsageReader.HasRecentUsage()
            };
            var path = Path.Combine(DirectoryPath, "status.json");
            temporary = path + $".{Environment.ProcessId}.tmp";
            File.WriteAllText(temporary,
                JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, path, true);
        }
        catch
        {
            // Diagnostics must never affect the always-on widget.
        }
        finally
        {
            try { if (temporary is not null && File.Exists(temporary)) File.Delete(temporary); }
            catch { }
        }
    }
}
