using System.Globalization;
using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static partial class Program
{
    // Real WPF trees with synthetic connection text. No controller, provider reads,
    // settings saves, registry writes or installed-app lifecycle are started here.
    private static int RunSettingsRedesignProbe(Assembly assembly)
    {
        var settingsType = RequiredType(assembly, "ClaudeUsageTray.TraySettings");
        var windowType = RequiredType(assembly, "ClaudeUsageTray.SettingsWindow");
        var themeType = RequiredType(assembly, "ClaudeUsageTray.WidgetVisualTheme");
        var preferenceType = RequiredType(assembly, "ClaudeUsageTray.ThemePreference");
        var themeManager = RequiredType(assembly, "ClaudeUsageTray.ThemeManager");
        var apply = themeManager.GetMethod("Apply")!;
        var constructor = windowType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
            null, [settingsType], null)!;
        var load = windowType.GetMethod("LoadValues", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var pages = new[] { "Display", "Appearance", "Connections", "Behavior", "Update", "Privacy" };
        var pageTitles = new Dictionary<string, string>
        {
            ["Display"] = "표시", ["Appearance"] = "꾸미기", ["Connections"] = "연결",
            ["Behavior"] = "동작", ["Update"] = "업데이트", ["Privacy"] = "개인정보"
        };
        var failures = new List<string>();
        var count = 0;
        var updateCount = 0;
        var preview = Environment.GetEnvironmentVariable("DEJAVU_SETTINGS_PREVIEW");
        if (!string.IsNullOrWhiteSpace(preview)) Directory.CreateDirectory(preview);

        foreach (var theme in Enum.GetNames(themeType))
        foreach (var preference in new[] { "Light", "Dark" })
        foreach (var minimum in new[] { false, true })
        {
            var settings = Activator.CreateInstance(settingsType)!;
            Set(settingsType, settings, "WidgetTheme", Enum.Parse(themeType, theme));
            Set(settingsType, settings, "Theme", Enum.Parse(preferenceType, preference));
            apply.Invoke(null, [settings]);
            var window = (Window)constructor.Invoke([settings]);
            load.Invoke(window, null); // _loading guards all persistence handlers.
            var shell = RequiredElement<Grid>(window, "WindowSurface");
            var size = new Size(minimum ? window.MinWidth : window.Width,
                                minimum ? window.MinHeight : window.Height);
            try
            {
                // Simulate long fallback/login states without consulting any credentials.
                RequiredElement<TextBlock>(window, "ClaudeConnectionTitle").Text = "Claude Desktop 기본 사용량 연결됨";
                RequiredElement<TextBlock>(window, "ClaudeConnectionDescription").Text =
                    "5시간·주간은 표시 중입니다. Fable 사용량을 확인하려면 Claude Code 설치와 로그인이 필요해요.";
                RequiredElement<Button>(window, "ClaudeConnectionButton").Visibility = Visibility.Visible;
                RequiredElement<Button>(window, "ClaudeConnectionButton").Content = "Claude Code 로그인";
                RequiredElement<TextBlock>(window, "CodexConnectionTitle").Text = "Codex Desktop 감지됨 · 로그인 필요";
                RequiredElement<TextBlock>(window, "CodexConnectionDescription").Text =
                    "CLI를 직접 사용하지 않아도 ChatGPT 로그인으로 Codex 사용량을 연결할 수 있어요.";
                RequiredElement<Button>(window, "CodexConnectionButton").Visibility = Visibility.Visible;
                RequiredElement<Button>(window, "CodexConnectionButton").Content = "브라우저 다시 열기";

                foreach (var page in pages)
                {
                    var prefix = $"theme={theme}, preference={preference}, minimum={minimum}, page={page}";
                    RequiredElement<RadioButton>(window, page + "Nav").IsChecked = true;
                    ArrangeSettings(shell, size);
                    var visible = pages.Where(name => RequiredElement<ScrollViewer>(window, name + "Panel").Visibility == Visibility.Visible).ToArray();
                    if (visible.Length != 1 || visible[0] != page) failures.Add(prefix + ": wrong active page");
                    var panel = RequiredElement<ScrollViewer>(window, page + "Panel");
                    // Settings use plain destination titles, not numbered kickers or slogans.
                    var heading = (panel.Content as StackPanel)?.Children.OfType<TextBlock>().FirstOrDefault();
                    if (heading?.Text != pageTitles[page])
                        failures.Add(prefix + ": nonfunctional page heading");
                    if (SettingsDescendants<TextBlock>(panel).Any(text =>
                            ReferenceEquals(text.Style, window.TryFindResource("SectionKicker"))))
                        failures.Add(prefix + ": redundant numbered kicker");
                    if (panel.HorizontalScrollBarVisibility != ScrollBarVisibility.Disabled)
                        failures.Add(prefix + ": horizontal overflow is enabled");
                    if (panel.ExtentWidth > panel.ViewportWidth + 1)
                        failures.Add(prefix + ": content exceeds viewport width");
                    VerifySettingsRows(window, panel, prefix, failures);
                    foreach (var picker in SettingsDescendants<ComboBox>(panel))
                    {
                        var text = picker.SelectedItem?.ToString() ?? "";
                        var formatted = new FormattedText(text, CultureInfo.CurrentCulture, FlowDirection.LeftToRight,
                            new Typeface(picker.FontFamily, picker.FontStyle, picker.FontWeight, picker.FontStretch),
                            picker.FontSize, Brushes.Black, VisualTreeHelper.GetDpi(picker).PixelsPerDip);
                        if (formatted.WidthIncludingTrailingWhitespace > picker.ActualWidth - 48 + 1)
                            failures.Add(prefix + $": picker label clips: {picker.Name}");
                        if (string.IsNullOrWhiteSpace(System.Windows.Automation.AutomationProperties.GetName(picker)))
                            failures.Add(prefix + $": unnamed picker: {picker.Name}");
                    }
                    if (!minimum && !string.IsNullOrWhiteSpace(preview) && (page == "Display" || page == "Appearance" || page == "Connections"))
                        SaveSettingsPreview(shell, size, Path.Combine(preview, $"{theme.ToLowerInvariant()}-{preference.ToLowerInvariant()}-{page.ToLowerInvariant()}.png"));
                    count++;
                }

                RequiredElement<RadioButton>(window, "UpdateNav").IsChecked = true;
                windowType.GetMethod("SetUpdateCheckLoading", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null);
                ArrangeSettings(shell, size);
                if (RequiredElement<Button>(window, "CheckUpdatesButton").IsEnabled ||
                    RequiredElement<ProgressBar>(window, "UpdateCheckProgress").Visibility != Visibility.Visible)
                    failures.Add($"{theme}/{preference}/{minimum}: update loading lost");
                updateCount++;
                windowType.GetMethod("SetUpdateCheckResult", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window,
                    ["새 버전을 확인하지 못했습니다. 네트워크 연결을 확인하고 잠시 후 다시 시도해 주세요.", false]);
                ArrangeSettings(shell, size);
                VerifySettingsRows(window, RequiredElement<ScrollViewer>(window, "UpdatePanel"),
                    $"{theme}/{preference}/{minimum}/update-error", failures);
                if (!RequiredElement<Button>(window, "CheckUpdatesButton").IsEnabled ||
                    RequiredElement<ProgressBar>(window, "UpdateCheckProgress").Visibility != Visibility.Collapsed)
                    failures.Add($"{theme}/{preference}/{minimum}: update result lost");
                updateCount++;
                if (!minimum && !string.IsNullOrWhiteSpace(preview))
                    SaveSettingsPreview(shell, size, Path.Combine(preview, $"{theme.ToLowerInvariant()}-{preference.ToLowerInvariant()}-update.png"));
            }
            finally
            {
                windowType.GetProperty("AllowClose", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(window, true);
                window.Close();
            }
        }
        Console.WriteLine($"Settings redesign matrix: {count} checked, {failures.Count} invalid");
        Console.WriteLine($"Settings inline update states: {updateCount} checked");
        foreach (var failure in failures) Console.Error.WriteLine("SETTINGS " + failure);
        return failures.Count;
    }

    private static void ArrangeSettings(FrameworkElement shell, Size size)
    {
        shell.Measure(size);
        shell.Arrange(new Rect(size));
        shell.UpdateLayout();
    }

    private static void VerifySettingsRows(Window window, ScrollViewer panel, string prefix, List<string> failures)
    {
        var rowStyle = window.FindResource("SettingRow");
        foreach (var row in SettingsDescendants<Border>(panel).Where(border => ReferenceEquals(border.Style, rowStyle)))
        {
            if (row.Child is not Grid grid) continue; // Stacked inline update result.
            if (grid.ColumnDefinitions.Count != 2) { failures.Add(prefix + ": row has no explicit columns"); continue; }
            var left = grid.Children.OfType<FrameworkElement>().FirstOrDefault(child => Grid.GetColumn(child) == 0);
            var right = grid.Children.OfType<FrameworkElement>().FirstOrDefault(child => Grid.GetColumn(child) == 1);
            if (left is null || right is null) { failures.Add(prefix + ": row column missing"); continue; }
            var leftBounds = left.TransformToAncestor(grid).TransformBounds(new Rect(left.RenderSize));
            var rightBounds = right.TransformToAncestor(grid).TransformBounds(new Rect(right.RenderSize));
            if (leftBounds.Right > rightBounds.Left + 0.5 || rightBounds.Right > grid.ActualWidth + 0.5)
                failures.Add(prefix + ": row label overlaps control or clips");
        }
        foreach (var text in SettingsDescendants<TextBlock>(panel))
        {
            if (text.ActualWidth <= 0 || text.ActualHeight <= 0 || string.IsNullOrEmpty(text.Text)) continue;
            // DesiredSize includes the element's margin; RenderSize does not.
            if (text.DesiredSize.Height - text.Margin.Top - text.Margin.Bottom > text.ActualHeight + 0.5)
                failures.Add(prefix + $": text clipped vertically: {text.Name}");
        }
    }

    private static IEnumerable<T> SettingsDescendants<T>(DependencyObject parent) where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T typed) yield return typed;
            foreach (var descendant in SettingsDescendants<T>(child)) yield return descendant;
        }
    }

    private static void SaveSettingsPreview(FrameworkElement shell, Size size, string path)
    {
        // Let normal toggle transitions reach their resting state before capture.
        var frame = new System.Windows.Threading.DispatcherFrame();
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start();
        System.Windows.Threading.Dispatcher.PushFrame(frame);
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(size.Width), (int)Math.Ceiling(size.Height), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(shell);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }
}
