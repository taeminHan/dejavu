using System.Text.Json;

namespace ClaudeUsageTray;

internal enum PrimaryMetric { FiveHour, Weekly, Fable, Codex }
internal enum TrayIconStyle { ClaudeMark, Percentage, Hidden }
internal enum WidgetDensity { Compact, Comfortable }
internal enum WidgetLayout { SingleRow, TwoRows }
internal enum ServiceDisplayMode { AutoDetect, ClaudeAndCodex, ClaudeOnly, CodexOnly }
internal enum WidgetPlacement { TaskbarRight, TopRight, Custom }
internal enum ThemePreference { System, Light, Dark }

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
    public bool FirstRunCompleted { get; set; }
    public bool ShowWidgetHeader { get; set; } = true;

    private static string FilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "dejavu", "settings.json");
    private static string LegacyFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "ClaudeUsageTray", "settings.json");

    public static TraySettings Load()
    {
        try
        {
            var source = File.Exists(FilePath) ? FilePath : LegacyFilePath;
            var settings = File.Exists(source)
                ? JsonSerializer.Deserialize<TraySettings>(File.ReadAllText(source)) ?? new TraySettings()
                : new TraySettings();
            settings.Normalize();
            if (source == LegacyFilePath && File.Exists(source)) settings.Save();
            return settings;
        }
        catch { return new TraySettings(); }
    }

    public void Save()
    {
        Normalize();
        var directory = Path.GetDirectoryName(FilePath)!;
        Directory.CreateDirectory(directory);
        var temporary = FilePath + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, FilePath, true);
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
