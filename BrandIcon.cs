using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using Drawing = System.Drawing;

namespace ClaudeUsageTray;

// Packaged Windows identity, separate from provider and usage-percentage icons.
// Every returned GDI icon belongs to its caller; no borrowed HICON outlives its source.
internal static class BrandIcon
{
    internal const string ApplicationIconUri = "pack://application:,,,/dejavu;component/assets/dejavu.ico";
    private const string ResourcePrefix = "ClaudeUsageTray.Brand.";
    private const string PersonalizeKey = @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize";
    private static readonly Lazy<ImageSource> ApplicationImageValue = new(LoadApplicationImage);

    public static ImageSource ApplicationImage => ApplicationImageValue.Value;

    internal static Drawing.Icon CreateApplicationIcon(int size = 32) => LoadIcon("dejavu.ico", size);

    // The explicit mode is also used by controller-free packaged-app validation.
    // Contrast themes use their live native background rather than cached WPF colors.
    internal static Drawing.Icon CreateTrayIcon(int size, bool lightTaskbar, bool highContrast = false)
    {
        if (highContrast)
        {
            var background = GetSysColor(5); // COLOR_WINDOW, COLORREF 0x00BBGGRR.
            lightTaskbar = IsLightBackground((byte)background, (byte)(background >> 8), (byte)(background >> 16));
        }
        return LoadIcon(lightTaskbar ? "dejavu-tray-dark.ico" : "dejavu-tray-light.ico", size);
    }

    internal static Drawing.Icon CreateTrayIconForSystem(int size)
    {
        var lightTaskbar = false;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(PersonalizeKey);
            lightTaskbar = key?.GetValue("SystemUsesLightTheme") is int value && value == 1;
        }
        catch
        {
            // A denied personalization key must not prevent startup. Dark is the Windows default.
        }
        return CreateTrayIcon(size, lightTaskbar, ThemeManager.IsHighContrastOn());
    }

    internal static bool IsLightBackground(byte red, byte green, byte blue)
    {
        static double Linear(byte channel)
        {
            var value = channel / 255.0;
            return value <= 0.04045 ? value / 12.92 : Math.Pow((value + 0.055) / 1.055, 2.4);
        }
        var luminance = 0.2126 * Linear(red) + 0.7152 * Linear(green) + 0.0722 * Linear(blue);
        var darkInkLuminance = 0.2126 * Linear(0x17) + 0.7152 * Linear(0x1C) + 0.0722 * Linear(0x17);
        // Pick the variant with the higher relative-luminance contrast, including custom colors.
        return (luminance + 0.05) / (darkInkLuminance + 0.05) >= 1.05 / (luminance + 0.05);
    }

    private static ImageSource LoadApplicationImage()
    {
        using var stream = OpenResource("dejavu.ico");
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var frame = decoder.Frames.OrderBy(value => value.PixelWidth).Last();
        frame.Freeze();
        return frame;
    }

    private static Drawing.Icon LoadIcon(string fileName, int size)
    {
        ArgumentOutOfRangeException.ThrowIfLessThan(size, 1);
        using var stream = OpenResource(fileName);
        using var icon = new Drawing.Icon(stream, size, size);
        return (Drawing.Icon)icon.Clone();
    }

    private static Stream OpenResource(string fileName) =>
        typeof(BrandIcon).Assembly.GetManifestResourceStream(ResourcePrefix + fileName)
        ?? throw new InvalidOperationException($"Missing packaged Dejavu identity resource: {fileName}");

    [DllImport("user32.dll")]
    private static extern uint GetSysColor(int index);
}
