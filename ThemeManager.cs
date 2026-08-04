using Microsoft.Win32;
using System.Windows;
using System.Windows.Media;

namespace ClaudeUsageTray;

internal static class ThemeManager
{
    public static void Apply(TraySettings settings)
    {
        var light = settings.Theme switch
        {
            ThemePreference.Light => true,
            ThemePreference.Dark => false,
            _ => IsSystemLight()
        };
        var accent = NormalizeColor(settings.AccentColor, "#6D8EFF");
        var palette = CreatePalette(settings.WidgetTheme, light, accent);
        // Transparent chrome exposes the text to an unpredictable desktop background.
        // Preserve the theme at normal opacity, then progressively prioritize legibility
        // for secondary and metric text as the chrome approaches its minimum opacity.
        var legibilityStrength = Math.Clamp((0.82 - settings.WidgetOpacity) / 0.27, 0, 1);
        var widgetMutedText = Blend(palette.WidgetMutedText, palette.WidgetText, legibilityStrength * 0.82);
        var widgetMetricText = Blend(palette.WidgetAccent, palette.WidgetText, legibilityStrength * 0.62);

        SetBrush("BackgroundBrush", palette.Background);
        SetBrush("SurfaceBrush", palette.Surface);
        SetBrush("SurfaceRaisedBrush", palette.SurfaceRaised);
        SetBrush("BorderBrush", palette.Border);
        SetBrush("WindowFrameBrush", palette.WindowFrame);
        SetBrush("TextBrush", palette.Text);
        SetBrush("MutedTextBrush", palette.MutedText);
        SetBrush("AccentBrush", palette.Accent);
        SetBrush("AccentSoftBrush", palette.AccentSoft);
        SetBrush("DangerBrush", palette.Danger);
        SetBrush("WarningBrush", palette.Warning);
        SetBrush("WidgetBackgroundBrush", palette.WidgetBackground);
        SetBrush("WidgetChromeBrush", MultiplyOpacity(palette.WidgetBackground, settings.WidgetOpacity));
        SetBrush("WidgetChromeRaisedBrush", MultiplyOpacity(palette.WidgetTrack, settings.WidgetOpacity));
        SetBrush("WidgetAccentBrush", palette.WidgetAccent);
        SetBrush("WidgetBorderBrush", palette.WidgetBorder);
        SetBrush("WidgetTextBrush", palette.WidgetText);
        SetBrush("WidgetMutedTextBrush", widgetMutedText);
        SetBrush("WidgetMetricTextBrush", widgetMetricText);
        SetBrush("WidgetTrackBrush", palette.WidgetTrack);
        SetBrush("ThemeGridBrush", palette.Grid);
        SetValue("AppFontFamily", new System.Windows.Media.FontFamily(palette.AppFont));
        SetValue("WidgetFontFamily", new System.Windows.Media.FontFamily(palette.WidgetFont));
        SetValue("WindowCornerRadius", new CornerRadius(palette.WindowRadius));
        SetValue("CardCornerRadius", new CornerRadius(palette.CardRadius));
        SetValue("ControlCornerRadius", new CornerRadius(palette.ControlRadius));
        SetValue("BadgeCornerRadius", new CornerRadius(palette.BadgeRadius));
        SetValue("ProgressCornerRadius", new CornerRadius(palette.ProgressRadius));
        SetValue("WindowFrameThickness", new Thickness(palette.FrameThickness));
        SetValue("CardBorderThickness", new Thickness(palette.CardBorderThickness));
        SetValue("UsageProgressHeight", palette.ProgressHeight);
        SetValue("ThemeMarkText", palette.Mark);
        SetValue("SettingsRowPadding", settings.WidgetTheme switch
        {
            WidgetVisualTheme.RetroNight => new Thickness(10, 12, 10, 12),
            WidgetVisualTheme.FluentGlass => new Thickness(14, 14, 14, 14),
            WidgetVisualTheme.TerminalMono => new Thickness(10, 11, 10, 11),
            WidgetVisualTheme.Orbit => new Thickness(12, 15, 12, 15),
            WidgetVisualTheme.PaperInk => new Thickness(4, 16, 4, 16),
            _ => new Thickness(0, 15, 0, 15)
        });
    }

    internal static string WidgetCardStyleKey(WidgetVisualTheme theme) => theme switch
    {
        WidgetVisualTheme.RetroNight => "WidgetCardRetroNight",
        WidgetVisualTheme.FluentGlass => "WidgetCardFluentGlass",
        WidgetVisualTheme.TerminalMono => "WidgetCardTerminalMono",
        WidgetVisualTheme.Orbit => "WidgetCardOrbit",
        WidgetVisualTheme.PaperInk => "WidgetCardPaperInk",
        _ => "WidgetCardModern"
    };

    internal static string WidgetProgressStyleKey(WidgetVisualTheme theme) => theme switch
    {
        WidgetVisualTheme.RetroNight => "RetroUsageProgress",
        WidgetVisualTheme.FluentGlass => "GlassUsageProgress",
        WidgetVisualTheme.TerminalMono => "TerminalUsageProgress",
        WidgetVisualTheme.Orbit => "OrbitUsageProgress",
        WidgetVisualTheme.PaperInk => "InkUsageProgress",
        _ => "UsageProgress"
    };

    internal static bool UsesThemedChrome(WidgetVisualTheme theme) => theme != WidgetVisualTheme.Modern;
    internal static bool UsesAngularChrome(WidgetVisualTheme theme) =>
        theme is WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono;
    internal static bool UsesMonospacedFont(WidgetVisualTheme theme) =>
        theme is WidgetVisualTheme.RetroNight or WidgetVisualTheme.TerminalMono;

    private static ThemePalette CreatePalette(WidgetVisualTheme theme, bool light, string accent)
    {
        var normalSoft = WithOpacity(accent, light ? 0.16 : 0.24);
        return theme switch
        {
            WidgetVisualTheme.RetroNight => new(
                "#090B14", "#0F1322", "#171C30", "#3B4260", "#68718F",
                "#ECE9DC", "#9BA2BB", BlendWithWhite(accent, 0.34), WithOpacity(accent, 0.28),
                "#FF7B83", "#F2B35F", "#0C0F1C", BlendWithWhite(accent, 0.34), "#454D70",
                "#ECE9DC", "#9BA2BB", "#191D2E", "#242A43",
                "Cascadia Mono, Consolas", "Cascadia Mono, Consolas", 0, 0, 0, 0, 0, 2, 1, 8, "▣"),
            WidgetVisualTheme.FluentGlass => light
                ? new("#F2F6FB", "#ECFFFFFF", "#DDE9F1FA", "#7C9AABBF", "#A9B7C7D8",
                    "#172033", "#657188", accent, WithOpacity(accent, 0.15), "#D9434A", "#A96716",
                    "#E8FFFFFF", accent, "#7794A9C1", "#172033", "#657188", "#C6E4EAF2", "#6A8DA5C2",
                    "Segoe UI Variable Text", "Segoe UI Variable Text", 18, 16, 12, 12, 6, 1, 1, 6, "◌")
                : new("#0C1119", "#E6151C27", "#D91F2937", "#6471889F", "#667F91A8",
                    "#F2F7FF", "#94A3B8", accent, WithOpacity(accent, 0.25), "#F07178", "#E6A756",
                    "#D9161D28", BlendWithWhite(accent, 0.18), "#718399B3", "#F2F7FF", "#94A3B8", "#B9253040", "#59758AA5",
                    "Segoe UI Variable Text", "Segoe UI Variable Text", 18, 16, 12, 12, 6, 1, 1, 6, "◌"),
            WidgetVisualTheme.TerminalMono => new(
                "#050806", "#08100B", "#0D1811", "#2B5237", "#4C7B59",
                "#D9F5DF", "#78A785", BlendWithWhite(accent, 0.2), WithOpacity(accent, 0.22),
                "#FF7A80", "#E8B65E", "#050A07", BlendWithWhite(accent, 0.2), "#356044",
                "#D9F5DF", "#78A785", "#102016", "#1A3925",
                "Cascadia Mono, Consolas", "Cascadia Mono, Consolas", 2, 0, 0, 0, 0, 1, 1, 7, ">_"),
            WidgetVisualTheme.Orbit => light
                ? new("#F1F6FB", "#FBFDFF", "#E6EFF7", "#B6CADD", "#91ABC5",
                    "#15243A", "#667E98", accent, WithOpacity(accent, 0.16), "#D9434A", "#A96716",
                    "#F8FCFF", BlendWithWhite(accent, 0.08), "#A8C1D8", "#15243A", "#667E98", "#DBE9F4", "#B4D3E7",
                    "Segoe UI Variable Text", "Segoe UI Variable Text", 16, 14, 10, 10, 6, 1, 1, 8, "◎")
                : new("#080E1B", "#0E182A", "#15243A", "#2F4A6B", "#476C94",
                    "#EDF5FF", "#87A0BC", BlendWithWhite(accent, 0.16), WithOpacity(accent, 0.25), "#F07178", "#E6A756",
                    "#0A1425", BlendWithWhite(accent, 0.24), "#33577B", "#EDF5FF", "#87A0BC", "#142942", "#204866",
                    "Segoe UI Variable Text", "Segoe UI Variable Text", 16, 14, 10, 10, 6, 1, 1, 8, "◎"),
            WidgetVisualTheme.PaperInk => light
                ? new("#F2EEE5", "#FBF8F0", "#EAE4D8", "#C9C0AF", "#AFA492",
                    "#2B2925", "#756F65", accent, WithOpacity(accent, 0.12), "#B84045", "#966019",
                    "#FAF7EF", accent, "#C6BDAE", "#2B2925", "#756F65", "#E5DED2", "#D3C7B7",
                    "./Assets/Fonts/#Nanum Pen Script", "./Assets/Fonts/#Nanum Pen Script", 6, 4, 3, 3, 0, 1, 1, 5, "✎")
                : new("#171714", "#211F1B", "#2A2721", "#4C473D", "#625C50",
                    "#EEE9DE", "#AAA295", accent, WithOpacity(accent, 0.2), "#E16A6F", "#D3A254",
                    "#1D1C18", BlendWithWhite(accent, 0.12), "#514B41", "#EEE9DE", "#AAA295", "#302C25", "#3B372F",
                    "./Assets/Fonts/#Nanum Pen Script", "./Assets/Fonts/#Nanum Pen Script", 6, 4, 3, 3, 0, 1, 1, 5, "✎"),
            _ => new(
                light ? "#F7F7F8" : "#101012", light ? "#FFFFFF" : "#18181B", light ? "#F1F1F3" : "#202024",
                light ? "#DCDCE1" : "#303036", light ? "#AEB3BE" : "#3A3A42", light ? "#18181B" : "#F7F7F8",
                light ? "#696974" : "#A1A1AA", accent, normalSoft, light ? "#D9434A" : "#F07178",
                light ? "#A96716" : "#E6A756", light ? "#FFFFFF" : "#18181B", accent,
                light ? "#DCDCE1" : "#303036", light ? "#18181B" : "#F7F7F8", light ? "#696974" : "#A1A1AA",
                light ? "#F1F1F3" : "#202024", light ? "#E5E5E8" : "#29292E",
                "Segoe UI Variable Text", "Segoe UI Variable Text", 12, 12, 8, 10, 2, 1, 1, 4, "◒")
        };
    }

    private static bool IsSystemLight()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value != 0;
        }
        catch { return false; }
    }

    private static void SetBrush(string key, string value) => SetValue(key,
        new System.Windows.Media.SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value)));
    private static void SetValue(string key, object value) => System.Windows.Application.Current.Resources[key] = value;

    private static string NormalizeColor(string? value, string fallback)
    {
        try
        {
            _ = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value ?? fallback);
            return value ?? fallback;
        }
        catch { return fallback; }
    }

    private static string WithOpacity(string value, double opacity)
    {
        var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value);
        var alpha = (byte)Math.Round(Math.Clamp(opacity, 0, 1) * 255);
        return $"#{alpha:X2}{color.R:X2}{color.G:X2}{color.B:X2}";
    }

    private static string MultiplyOpacity(string value, double opacity)
    {
        var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value);
        var alpha = (byte)Math.Round(color.A * Math.Clamp(opacity, 0, 1));
        return $"#{alpha:X2}{color.R:X2}{color.G:X2}{color.B:X2}";
    }

    private static string BlendWithWhite(string value, double amount)
    {
        var color = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value);
        var blend = Math.Clamp(amount, 0, 1);
        static byte Mix(byte channel, double blendValue) =>
            (byte)Math.Round(channel + (255 - channel) * blendValue);
        return $"#{Mix(color.R, blend):X2}{Mix(color.G, blend):X2}{Mix(color.B, blend):X2}";
    }

    private static string Blend(string value, string target, double amount)
    {
        var sourceColor = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value);
        var targetColor = (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(target);
        var blend = Math.Clamp(amount, 0, 1);
        static byte Mix(byte source, byte destination, double blendValue) =>
            (byte)Math.Round(source + (destination - source) * blendValue);
        return $"#{Mix(sourceColor.A, targetColor.A, blend):X2}{Mix(sourceColor.R, targetColor.R, blend):X2}" +
               $"{Mix(sourceColor.G, targetColor.G, blend):X2}{Mix(sourceColor.B, targetColor.B, blend):X2}";
    }

    private sealed record ThemePalette(
        string Background, string Surface, string SurfaceRaised, string Border, string WindowFrame,
        string Text, string MutedText, string Accent, string AccentSoft, string Danger, string Warning,
        string WidgetBackground, string WidgetAccent, string WidgetBorder, string WidgetText,
        string WidgetMutedText, string WidgetTrack, string Grid, string AppFont, string WidgetFont,
        double WindowRadius, double CardRadius, double ControlRadius, double BadgeRadius, double ProgressRadius,
        double FrameThickness, double CardBorderThickness, double ProgressHeight, string Mark);
}
