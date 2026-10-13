using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static partial class Program
{
    // Actual native trees with synthetic state only. No controller, credential/history
    // reads, provider requests, settings saves, registry writes or visible windows.
    private static int RunWindowsThemeRegressionProbe(Assembly assembly, StateFactory factory)
    {
        var failures = new List<string>();
        var settingsType = RequiredType(assembly, "ClaudeUsageTray.TraySettings");
        var themeType = RequiredType(assembly, "ClaudeUsageTray.WidgetVisualTheme");
        var preferenceType = RequiredType(assembly, "ClaudeUsageTray.ThemePreference");
        var detailsType = RequiredType(assembly, "ClaudeUsageTray.UsageDetailsWindow");
        var onboardingType = RequiredType(assembly, "ClaudeUsageTray.OnboardingWindow");
        var updateType = RequiredType(assembly, "ClaudeUsageTray.UpdateWindow");
        var apply = RequiredType(assembly, "ClaudeUsageTray.ThemeManager").GetMethod("Apply")!;
        var onboardingConstructor = onboardingType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
            null, [settingsType, typeof(bool)], null)!;
        var count = 0;

        foreach (var appearance in new[] { "Light", "Dark" })
        foreach (var theme in Enum.GetNames(themeType))
        {
            var settings = Activator.CreateInstance(settingsType)!;
            Set(settingsType, settings, "WidgetTheme", Enum.Parse(themeType, theme));
            Set(settingsType, settings, "Theme", Enum.Parse(preferenceType, appearance));
            apply.Invoke(null, [settings]);
            var prefix = $"{appearance}/{theme}";
            var raised = Application.Current.TryFindResource("SurfaceRaisedBrush") as SolidColorBrush;
            if (raised is null) failures.Add(prefix + ": missing SurfaceRaisedBrush");

            var details = (Window)Activator.CreateInstance(detailsType, nonPublic: true)!;
            try
            {
                detailsType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .Invoke(details, [factory.Create(true, true), settings]);
                ArrangeThemeRegressionTree(details);
                if (theme == "FluentGlass")
                    foreach (var name in new[] { "ClaudeCard", "CodexCard" })
                        VerifyRaisedBackground(details, name, raised, prefix + "/details", failures);
                if (theme == "TerminalMono")
                    VerifyRaisedBackground(details, "CreditsCard", raised, prefix + "/details", failures);
                if (theme is "RetroNight" or "TerminalMono")
                    foreach (var name in new[] { "ClaudeFiveRow", "ClaudeWeeklyRow", "ClaudeFableRow", "CodexFiveRow", "CodexWeeklyRow" })
                        VerifyRaisedBackground(details, name, raised, prefix + "/details", failures);
                SaveThemeRegressionPreview(details, appearance + "-" + theme + "-details");
                count++;
            }
            finally { details.Close(); }

            var onboarding = (Window)onboardingConstructor.Invoke([settings, false]);
            try
            {
                ArrangeThemeRegressionTree(onboarding);
                if (theme is "FluentGlass" or "TerminalMono" or "Orbit")
                    foreach (var name in new[] { "ClaudeCredentialCard", "CodexCredentialCard" })
                        VerifyRaisedBackground(onboarding, name, raised, prefix + "/onboarding", failures);
                SaveThemeRegressionPreview(onboarding, appearance + "-" + theme + "-onboarding");
                count++;
            }
            finally { onboarding.Close(); }

            var update = (Window)Activator.CreateInstance(updateType, nonPublic: true)!;
            try
            {
                updateType.GetMethod("ApplyTheme", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .Invoke(update, [Enum.Parse(themeType, theme)]);
                ArrangeThemeRegressionTree(update);
                if (theme is "RetroNight" or "TerminalMono")
                    VerifyRaisedBackground(update, "UpdateTitleBar", raised, prefix + "/update", failures);
                if (theme is "FluentGlass" or "Orbit")
                    VerifyRaisedBackground(update, "UpdateNotesCard", raised, prefix + "/update", failures);
                SaveThemeRegressionPreview(update, appearance + "-" + theme + "-update");
                count++;
            }
            finally
            {
                updateType.GetProperty("AllowClose", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(update, true);
                update.Close();
            }
        }

        var accentCount = VerifyDefaultAndSavedAccents(assembly, settingsType, failures);
        Console.WriteLine($"Windows theme resource matrix: {count} checked, {failures.Count} failures");
        Console.WriteLine($"Windows accent defaults: {accentCount} checked");
        foreach (var failure in failures) Console.Error.WriteLine("THEME REGRESSION " + failure);
        return failures.Count;
    }

    private static void ArrangeThemeRegressionTree(Window window)
    {
        var root = (FrameworkElement)window.Content;
        var size = new Size(window.Width, double.IsFinite(window.Height) ? window.Height : window.MaxHeight);
        root.Measure(size);
        root.Arrange(new Rect(size));
        root.UpdateLayout();
    }

    private static void VerifyRaisedBackground(Window window, string name, SolidColorBrush? expected,
        string prefix, List<string> failures)
    {
        var element = window.FindName(name);
        var actual = element switch
        {
            Border border => border.Background as SolidColorBrush,
            Panel panel => panel.Background as SolidColorBrush,
            _ => null
        };
        if (expected is null || actual is null || actual.Color != expected.Color)
            failures.Add(prefix + ": unresolved/wrong raised background: " + name);
    }

    private static void SaveThemeRegressionPreview(Window window, string name)
    {
        var directory = Environment.GetEnvironmentVariable("DEJAVU_THEME_REGRESSION_PREVIEW");
        if (string.IsNullOrWhiteSpace(directory)) return;
        var root = (FrameworkElement)window.Content;
        Directory.CreateDirectory(directory);
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(root.RenderSize.Width),
            (int)Math.Ceiling(root.RenderSize.Height), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(root);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var output = File.Create(Path.Combine(directory, name + ".png"));
        encoder.Save(output);
    }

    private static int VerifyDefaultAndSavedAccents(Assembly assembly, Type settingsType, List<string> failures)
    {
        var windowType = RequiredType(assembly, "ClaudeUsageTray.SettingsWindow");
        var constructor = windowType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
            null, [settingsType], null)!;
        var settings = Activator.CreateInstance(settingsType)!;
        var defaultAccent = (string)settingsType.GetProperty("AccentColor")!.GetValue(settings)!;
        var window = (Window)constructor.Invoke([settings]);
        // Suppress Checked persistence handlers, exactly as LoadValues does in production.
        windowType.GetField("_loading", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(window, true);
        var updateSelection = windowType.GetMethod("UpdateAccentSelection", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var colors = new[] { "BlueAccent", "PurpleAccent", "CoralAccent", "GreenAccent" };
        var count = 0;
        try
        {
            var blue = RequiredElement<RadioButton>(window, "BlueAccent");
            updateSelection.Invoke(window, null);
            if (!string.Equals(blue.Tag as string, defaultAccent, StringComparison.OrdinalIgnoreCase) || blue.IsChecked != true)
                failures.Add("accent: fresh default does not select BlueAccent");
            count++;

            // Existing values, including the old blue and arbitrary custom colors,
            // must survive opening Settings; a new default is not a migration.
            foreach (var value in new[] { "#6D8EFF", "#8B7CF6", "#123456" })
            {
                Set(settingsType, settings, "AccentColor", value);
                updateSelection.Invoke(window, null);
                var selected = colors.Select(name => RequiredElement<RadioButton>(window, name))
                    .Where(button => button.IsChecked == true).ToArray();
                var matches = colors.Select(name => RequiredElement<RadioButton>(window, name))
                    .Where(button => string.Equals(button.Tag as string, value, StringComparison.OrdinalIgnoreCase)).ToArray();
                if ((string)settingsType.GetProperty("AccentColor")!.GetValue(settings)! != value ||
                    !selected.SequenceEqual(matches))
                    failures.Add("accent: stored value or selection changed: " + value);
                count++;
            }

            windowType.GetMethod("RestoreDefaultsInMemory", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null);
            updateSelection.Invoke(window, null);
            if ((string)settingsType.GetProperty("AccentColor")!.GetValue(settings)! != defaultAccent || blue.IsChecked != true)
                failures.Add("accent: reset differs from fresh default");
            count++;
        }
        finally
        {
            windowType.GetProperty("AllowClose", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(window, true);
            window.Close();
        }
        return count;
    }
}
