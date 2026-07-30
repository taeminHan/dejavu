using Microsoft.Win32;

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

        Set("BackgroundBrush", light ? "#F7F7F8" : "#101012");
        Set("SurfaceBrush", light ? "#FFFFFF" : "#18181B");
        Set("SurfaceRaisedBrush", light ? "#F1F1F3" : "#202024");
        Set("BorderBrush", light ? "#DCDCE1" : "#303036");
        Set("TextBrush", light ? "#18181B" : "#F7F7F8");
        Set("MutedTextBrush", light ? "#696974" : "#A1A1AA");
        var accent = NormalizeColor(settings.AccentColor, "#6D8EFF");
        Set("AccentBrush", accent);
        Set("AccentSoftBrush", WithOpacity(accent, light ? 0.16 : 0.24));
        Set("DangerBrush", light ? "#D9434A" : "#F07178");
        Set("WarningBrush", light ? "#A96716" : "#E6A756");
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

    private static void Set(string key, string value) =>
        System.Windows.Application.Current.Resources[key] = new System.Windows.Media.SolidColorBrush(
            (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value));

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
}
