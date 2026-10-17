using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;
using Application = System.Windows.Application;
using Image = System.Windows.Controls.Image;
using Size = System.Windows.Size;
using Color = System.Windows.Media.Color;

namespace ClaudeUsageTray;

// Explicit release acceptance mode. Uses in-memory fixtures and the actual packaged
// resources/windows, never the controller, local settings, providers or update service.
// An output directory must be empty; existing evidence is never overwritten.
internal static class BrandValidation
{
    internal static int Run(string outputDirectory)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(outputDirectory) || !Path.IsPathFullyQualified(outputDirectory))
                throw new ArgumentException("Brand validation requires an absolute output directory.");
            outputDirectory = Path.GetFullPath(outputDirectory);
            if (Directory.Exists(outputDirectory) && Directory.EnumerateFileSystemEntries(outputDirectory).Any())
                throw new IOException("Brand validation output directory is not empty.");
            Directory.CreateDirectory(outputDirectory);

            var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            application.Resources.MergedDictionaries.Add(new ResourceDictionary
            {
                Source = new Uri("/dejavu;component/ThemeResources.xaml", UriKind.Relative)
            });
            var failures = new List<string>();
            var exports = new List<string>();
            var windowCases = 0;
            var trayCases = 0;
            var paletteCases = 0;
            if (!BrandIcon.IsLightBackground(255, 255, 255) || BrandIcon.IsLightBackground(0, 0, 0) ||
                !BrandIcon.IsLightBackground(255, 255, 0) || BrandIcon.IsLightBackground(0, 0, 255))
                failures.Add("tray contrast foreground selection does not maximize contrast");
            var now = DateTimeOffset.FromUnixTimeSeconds(1_800_000_000);
            var state = new ApplicationState(UsageStatus.Ready,
                new UsageSnapshot(new(42, now.AddHours(1)), new(73, now.AddDays(1)), new(91, now.AddDays(1))),
                "합성 사용량 · 실제 계정 아님", now, CodexSnapshot:
                new CodexUsageSnapshot(new(27, now.AddHours(2)), new(61, now.AddDays(2)), 0, now.AddDays(7), "fixture"),
                ClaudeStatus: UsageStatus.Ready, CodexStatus: UsageStatus.Ready,
                ClaudeMessage: "합성 Claude 사용량", CodexMessage: "합성 Codex 사용량");

            var applicationPixels = RenderImage(BrandIcon.ApplicationImage, 64);
            VerifyPalette(applicationPixels, "application", failures);
            SaveBitmap(applicationPixels, "application.png");
            paletteCases++;
            foreach (var light in new[] { true, false })
            foreach (var size in new[] { 16, 20, 24, 32, 48 })
            {
                using var icon = BrandIcon.CreateTrayIcon(size, light);
                using var bitmap = icon.ToBitmap();
                var name = $"tray-{(light ? "light" : "dark")}-{size}.png";
                bitmap.Save(Path.Combine(outputDirectory, name), Drawing.Imaging.ImageFormat.Png);
                exports.Add(name);
                var visible = 0;
                var opaqueDark = 0;
                var opaqueLight = 0;
                for (var y = 0; y < bitmap.Height; y++)
                for (var x = 0; x < bitmap.Width; x++)
                {
                    var pixel = bitmap.GetPixel(x, y);
                    if (pixel.A > 0) visible++;
                    if (pixel.A > 200 && pixel.R < 64 && pixel.G < 64 && pixel.B < 64) opaqueDark++;
                    if (pixel.A > 200 && pixel.R > 192 && pixel.G > 192 && pixel.B > 192) opaqueLight++;
                }
                if (bitmap.Width != size || bitmap.Height != size || visible == 0 ||
                    visible == bitmap.Width * bitmap.Height || (light ? opaqueDark : opaqueLight) == 0)
                    failures.Add($"tray/{light}/{size}: wrong size, transparency or foreground");
                // Golden interior/void samples distinguish the approved open frame
                // silhouette from an old filled circular/clock product mark.
                if (bitmap.GetPixel(size / 2, size / 2).A != 0 ||
                    bitmap.GetPixel(size / 2, (int)(size * .2)).A < 128 ||
                    bitmap.GetPixel((int)(size * .2), size / 2).A < 128 ||
                    bitmap.GetPixel((int)(size * .8), size / 2).A < 128)
                    failures.Add($"tray/{light}/{size}: approved open-frame silhouette is missing");
                trayCases++;
            }
            using (var highContrast = BrandIcon.CreateTrayIcon(32, lightTaskbar: true, highContrast: true))
            using (var bitmap = highContrast.ToBitmap())
            {
                bitmap.Save(Path.Combine(outputDirectory, "tray-high-contrast-policy.png"), Drawing.Imaging.ImageFormat.Png);
                exports.Add("tray-high-contrast-policy.png");
                trayCases++;
            }

            foreach (var appearance in new[] { ThemePreference.Light, ThemePreference.Dark })
            foreach (var theme in Enum.GetValues<WidgetVisualTheme>())
            {
                var settings = new TraySettings { Theme = appearance, WidgetTheme = theme,
                    ServiceDisplayMode = ServiceDisplayMode.ClaudeAndCodex, AutomaticUpdateChecksEnabled = false };
                ThemeManager.Apply(settings);
                var shared = application.FindResource("DejavuBrandImage") as ImageSource
                    ?? throw new InvalidOperationException("Shared product mark missing.");
                VerifyPalette(RenderImage(shared, 64), $"{appearance}/{theme}/header", failures);
                paletteCases++;
                var windows = new (Window Window, string Name, string Mark)[]
                {
                    (new SettingsWindow(settings), "settings", "SettingsMark"),
                    (new OnboardingWindow(settings, detectCredentials: false), "onboarding", "OnboardingBrandMark"),
                    (new UsageDetailsWindow(), "details", "DetailsBrandMark"),
                    (new UpdateWindow(), "update", "UpdateBrandMark")
                };
                try
                {
                    ((UsageDetailsWindow)windows[2].Window).UpdateState(state, settings);
                    ((UpdateWindow)windows[3].Window).ApplyTheme(theme);
                    foreach (var item in windows)
                    {
                        var prefix = $"{appearance}/{theme}/{item.Name}";
                        if (!ReferenceEquals(item.Window.Icon, BrandIcon.ApplicationImage))
                            failures.Add(prefix + ": window icon is not the packaged application icon");
                        if (item.Window.FindName(item.Mark) is not Image image ||
                            !ReferenceEquals(image.Source, shared) || image.Visibility != Visibility.Visible)
                            failures.Add(prefix + ": product header is not the shared mark");
                        SaveWindow(item.Window, $"{appearance}-{theme}-{item.Name}.png");
                        windowCases++;
                    }
                }
                finally
                {
                    ((SettingsWindow)windows[0].Window).AllowClose = true;
                    ((UpdateWindow)windows[3].Window).AllowClose = true;
                    foreach (var item in windows) item.Window.Close();
                }
            }

            // Exercise the real notification-area API with the exact runtime factory.
            // No controller or provider is started and the owned icon is always removed.
            using (var trayIcon = BrandIcon.CreateTrayIcon(Forms.SystemInformation.SmallIconSize.Width, lightTaskbar: false))
            using (var tray = new Forms.NotifyIcon { Icon = trayIcon, Text = "Dejavu · brand acceptance (synthetic)", Visible = true })
            {
                Forms.Application.DoEvents();
                if (!tray.Visible || tray.Icon is null) failures.Add("notification-area icon assignment failed");
                tray.Visible = false;
            }

            var report = new
            {
                schemaVersion = 1, success = failures.Count == 0,
                version = VelopackUpdateService.CurrentVersion,
                executable = Environment.ProcessPath, windowCases, trayCases, paletteCases,
                notificationAreaAssignment = true,
                scope = "Packaged runtime resources and synthetic WPF trees; no user settings, credentials, providers or updater. Not physical-DPI or interactive Explorer acceptance.",
                failures, exports
            };
            File.WriteAllText(Path.Combine(outputDirectory, "brand-validation.json"),
                JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine($"Windows packaged brand runtime: {windowCases} windows, {trayCases} tray cases, {paletteCases} palettes, {failures.Count} failures");
            application.Shutdown();
            return failures.Count == 0 ? 0 : 1;

            void SaveBitmap(BitmapSource bitmap, string name)
            {
                var encoder = new PngBitmapEncoder();
                encoder.Frames.Add(BitmapFrame.Create(bitmap));
                using var stream = new FileStream(Path.Combine(outputDirectory, name), FileMode.CreateNew);
                encoder.Save(stream);
                exports.Add(name);
            }

            void SaveWindow(Window window, string name)
            {
                var root = (FrameworkElement)window.Content;
                var height = double.IsFinite(window.Height) ? window.Height :
                    double.IsFinite(window.MaxHeight) ? window.MaxHeight : 800;
                var size = new Size(window.Width, height);
                root.Measure(size);
                root.Arrange(new Rect(size));
                root.UpdateLayout();
                // A root Margin is a VisualOffset and must fit inside the capture.
                // Rendering only root.RenderSize would cut off Onboarding's right/bottom.
                var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width),
                    (int)Math.Ceiling(size.Height), 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(root);
                SaveBitmap(bitmap, name);
            }
        }
        catch (Exception exception)
        {
            // Do not use the production crash log or touch AppData from validation.
            Console.Error.WriteLine($"Brand validation failed: {exception.GetType().Name}");
            return 1;
        }
    }

    private static BitmapSource RenderImage(ImageSource source, int size)
    {
        var visual = new DrawingVisual();
        using (var drawing = visual.RenderOpen())
            drawing.DrawImage(source, new Rect(0, 0, size, size));
        var bitmap = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(visual);
        return bitmap;
    }

    private static void VerifyPalette(BitmapSource image, string name, List<string> failures)
    {
        var pixels = new byte[image.PixelWidth * image.PixelHeight * 4];
        image.CopyPixels(pixels, image.PixelWidth * 4, 0);
        foreach (var color in new[] { Color.FromRgb(221, 226, 210), Color.FromRgb(32, 62, 46), Color.FromRgb(151, 167, 137) })
        {
            var found = false;
            for (var i = 0; i < pixels.Length; i += 4)
                if (pixels[i] == color.B && pixels[i + 1] == color.G && pixels[i + 2] == color.R && pixels[i + 3] == 255)
                { found = true; break; }
            if (!found) failures.Add($"{name}: approved fixed brand color {color} missing");
        }
    }
}
