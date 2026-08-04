using System.Text.Json;

namespace ClaudeUsageTray;

internal enum PrimaryMetric { FiveHour, Weekly, Fable, Codex }
internal enum TrayIconStyle { ClaudeMark, Percentage, Hidden }
// Keep the existing numeric values so rc.2 settings migrate without changing size.
internal enum WidgetDensity { Compact = 0, Comfortable = 1, Small = 2 }
internal enum WidgetLayout { SingleRow, TwoRows }
internal enum ServiceDisplayMode { AutoDetect, ClaudeAndCodex, ClaudeOnly, CodexOnly }
internal enum WidgetPlacement { TaskbarRight, TopRight, Custom }
internal enum ThemePreference { System, Light, Dark }
internal enum WidgetVisualTheme { Modern, RetroNight, FluentGlass, TerminalMono, Orbit, PaperInk }

internal sealed class TraySettings
{
    public PrimaryMetric PrimaryMetric { get; set; } = PrimaryMetric.FiveHour;
    public bool ShowProgressBars { get; set; } = true;
    public double WidgetOpacity { get; set; } = 0.9;
    public int? WidgetLeft { get; set; }
    public int? WidgetTop { get; set; }
    public string BackgroundColor { get; set; } = "#1E1E20";
    public string AccentColor { get; set; } = "#3A96F6";
    public string TextColor { get; set; } = "#AEAEB4";
    public bool UseThresholdColors { get; set; } = true;
    public int RefreshSeconds { get; set; } = 60;
    public TrayIconStyle TrayIconStyle { get; set; } = TrayIconStyle.ClaudeMark;
    public WidgetDensity WidgetDensity { get; set; } = WidgetDensity.Compact;
    public WidgetLayout WidgetLayout { get; set; } = WidgetLayout.SingleRow;
    public ServiceDisplayMode ServiceDisplayMode { get; set; } = ServiceDisplayMode.AutoDetect;
    public WidgetPlacement WidgetPlacement { get; set; } = WidgetPlacement.TaskbarRight;
    public ThemePreference Theme { get; set; } = ThemePreference.System;
    public WidgetVisualTheme WidgetTheme { get; set; } = WidgetVisualTheme.Modern;
    public bool FirstRunCompleted { get; set; }
    public bool CheckForUpdatesOnStartup { get; set; } = true;

    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "dejavu", "settings.json");
    private static string LegacyFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ClaudeUsageTray", "settings.json");

    public static TraySettings Load()
    {
        var source = File.Exists(FilePath) ? FilePath : LegacyFilePath;
        try
        {
            var settings = File.Exists(source)
                ? JsonSerializer.Deserialize<TraySettings>(File.ReadAllText(source)) ?? new TraySettings()
                : new TraySettings();
            settings.Normalize();
            if (source == LegacyFilePath && File.Exists(source)) settings.Save();
            return settings;
        }
        catch
        {
            PreserveCorruptSettings(source);
            return new TraySettings();
        }
    }

    public bool Save()
    {
        Normalize();
        var temporary = FilePath + ".tmp";
        try
        {
            var directory = Path.GetDirectoryName(FilePath)!;
            Directory.CreateDirectory(directory);
            File.WriteAllText(temporary, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(temporary, FilePath, true);
            return true;
        }
        catch
        {
            try { if (File.Exists(temporary)) File.Delete(temporary); }
            catch { }
            return false;
        }
    }

    private void Normalize()
    {
        WidgetOpacity = Math.Clamp(WidgetOpacity, 0.55, 1.0);
        RefreshSeconds = Math.Clamp(RefreshSeconds, 60, 300);
        if (!Enum.IsDefined(PrimaryMetric)) PrimaryMetric = PrimaryMetric.FiveHour;
        if (!Enum.IsDefined(TrayIconStyle)) TrayIconStyle = TrayIconStyle.ClaudeMark;
        if (!Enum.IsDefined(WidgetDensity)) WidgetDensity = WidgetDensity.Compact;
        if (!Enum.IsDefined(WidgetLayout)) WidgetLayout = WidgetLayout.SingleRow;
        if (!Enum.IsDefined(ServiceDisplayMode)) ServiceDisplayMode = ServiceDisplayMode.AutoDetect;
        if (!Enum.IsDefined(WidgetPlacement)) WidgetPlacement = WidgetPlacement.TaskbarRight;
        if (!Enum.IsDefined(Theme)) Theme = ThemePreference.System;
        if (!Enum.IsDefined(WidgetTheme)) WidgetTheme = WidgetVisualTheme.Modern;
        BackgroundColor = NormalizeColor(BackgroundColor, "#1E1E20");
        AccentColor = NormalizeColor(AccentColor, "#3A96F6");
        TextColor = NormalizeColor(TextColor, "#AEAEB4");
    }

    private static string NormalizeColor(string? value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value)) return fallback;
        try
        {
            _ = System.Windows.Media.ColorConverter.ConvertFromString(value);
            return value;
        }
        catch { return fallback; }
    }

    private static void PreserveCorruptSettings(string source)
    {
        try
        {
            if (!File.Exists(source)) return;
            var directory = Path.GetDirectoryName(source)!;
            var backup = Path.Combine(directory, $"settings.corrupt-{DateTime.Now:yyyyMMdd-HHmmss}.json");
            File.Move(source, backup, false);
        }
        catch
        {
            // A read-only or locked settings file must not prevent startup.
        }
    }

    internal (bool Claude, bool Codex) ResolveServices(ApplicationState state) => ServiceDisplayMode switch
    {
        ServiceDisplayMode.ClaudeAndCodex => (true, true),
        ServiceDisplayMode.ClaudeOnly => (true, false),
        ServiceDisplayMode.CodexOnly => (false, true),
        _ => (state.Snapshot is not null || state.ClaudeStatus == UsageStatus.Ready,
              state.CodexSnapshot is not null || state.CodexStatus == UsageStatus.Ready)
    };
}
