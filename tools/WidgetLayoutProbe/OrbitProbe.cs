using System.IO;
using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static partial class Program
{
    private static int RunOrbitProbe(Assembly assembly, StateFactory factory)
    {
        var failures = new List<string>();
        var cases = 0;
        var settingsType = RequiredType(assembly, "ClaudeUsageTray.TraySettings");
        var windowType = RequiredType(assembly, "ClaudeUsageTray.UsageWidgetWindow");
        var detailsType = RequiredType(assembly, "ClaudeUsageTray.UsageDetailsWindow");
        var apply = RequiredType(assembly, "ClaudeUsageTray.ThemeManager").GetMethod("Apply")!;
        var preview = Environment.GetEnvironmentVariable("DEJAVU_ORBIT_PREVIEW");
        if (preview is not null) Directory.CreateDirectory(preview);
        foreach (var light in new[] { false, true })
        foreach (var density in new[] { "Small", "Compact", "Comfortable" })
        foreach (var rows in new[] { "SingleRow", "TwoRows" })
        foreach (var progress in new[] { true, false })
        foreach (var variant in new[] { "both", "weekly", "five", "expired", "unknown" })
        {
            var settings = Activator.CreateInstance(settingsType)!;
            void Option(string property, string value) => Set(settingsType, settings, property,
                Enum.Parse(settingsType.GetProperty(property)!.PropertyType, value));
            Option("WidgetTheme", "Orbit");
            Option("Theme", light ? "Light" : "Dark");
            Option("WidgetDensity", density);
            Option("WidgetLayout", rows);
            Option("ServiceDisplayMode", "ClaudeAndCodex");
            Set(settingsType, settings, "ShowProgressBars", progress);
            apply.Invoke(null, [settings]);
            var state = factory.Create(true, true, variant is "both" or "five", variant is "both" or "weekly" or "expired",
                variant == "expired");
            if (variant == "both")
            {
                var claude = Get(state, "Snapshot")!;
                var codexData = Get(state, "CodexSnapshot")!;
                var limit = RequiredType(assembly, "ClaudeUsageTray.UsageLimit");
                Set(claude.GetType(), claude, "FiveHour", Activator.CreateInstance(limit, [8d, DateTimeOffset.Now.AddHours(2)])!);
                Set(claude.GetType(), claude, "Weekly", Activator.CreateInstance(limit, [24d, DateTimeOffset.Now.AddDays(3)])!);
                Set(claude.GetType(), claude, "Fable", Activator.CreateInstance(limit, [63d, DateTimeOffset.Now.AddDays(3)])!);
                Set(codexData.GetType(), codexData, "FiveHour", Activator.CreateInstance(limit, [0d, DateTimeOffset.Now.AddHours(4)])!);
                Set(codexData.GetType(), codexData, "Weekly", Activator.CreateInstance(limit, [36d, DateTimeOffset.Now.AddDays(4)])!);
                Set(codexData.GetType(), codexData, "ResetCredits", 3);
            }
            Set(state.GetType(), state, "Message", "Claude · Codex 사용량이 최신 상태입니다");
            Set(state.GetType(), state, "ClaudeMessage", "최신");
            Set(state.GetType(), state, "CodexMessage", "최신");
            Set(state.GetType(), state, "UpdatedAt", DateTimeOffset.Now);
            var widget = (Window)Activator.CreateInstance(windowType, BindingFlags.Instance | BindingFlags.NonPublic,
                null, [settings], null)!;
            windowType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(widget, [state]);
            var card = RequiredElement<FrameworkElement>(widget, "WidgetCard");
            card.Measure(new Size(widget.Width, double.PositiveInfinity));
            card.Arrange(new Rect(0, 0, widget.Width, widget.Height));
            card.UpdateLayout();
            var prefix = $"{light}/{density}/{rows}/{progress}/{variant}";
            foreach (var name in new[] { "OrbitClaudeSystem", "OrbitCodexSystem" })
            {
                var system = RequiredElement<FrameworkElement>(widget, name);
                CheckOrbitTree(system, card, prefix, failures);
                var chart = ((Grid)system).Children.OfType<FrameworkElement>().Single(e => e.GetType().Name == "OrbitSystemChart");
                if ((chart.Visibility == Visibility.Visible) != progress) failures.Add(prefix + ": progress visibility");
                var widgetBodies = ((System.Collections.IEnumerable)Get(chart, "Metrics")!).Cast<object>()
                    .Select(metric => Get(metric, "Body")!.ToString());
                var expectedBodies = name == "OrbitClaudeSystem" ? "Venus,Earth,Mars"
                    : variant is "both" or "expired" ? "Jupiter,Saturn"
                    : variant == "five" ? "Jupiter" : "Saturn";
                if (string.Join(",", widgetBodies) != expectedBodies)
                    failures.Add(prefix + ": widget solar order " + name);
            }
            var codex = RequiredElement<Grid>(widget, "OrbitCodexSystem");
            var values = Descendants(codex).OfType<TextBlock>().Select(t => t.Text).Where(t => t.EndsWith('%')).ToArray();
            var expectedCount = variant is "both" or "expired" ? 2 : 1;
            if (values.Length != expectedCount || (variant == "expired" && !values.Contains("--%")))
                failures.Add(prefix + ": optional/expired Codex window semantics");

            var details = (Window)Activator.CreateInstance(detailsType, nonPublic: true)!;
            detailsType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(details, [state, settings]);
            var detailsCard = RequiredElement<FrameworkElement>(details, "DetailsCard");
            detailsCard.Measure(new Size(details.Width, double.PositiveInfinity));
            detailsCard.Arrange(new Rect(0, 0, details.Width, detailsCard.DesiredSize.Height));
            detailsCard.UpdateLayout();
            if (detailsCard.DesiredSize.Height > details.MaxHeight) failures.Add(prefix + ": detail height");
            var solar = RequiredElement<FrameworkElement>(details, "SolarSystem");
            CheckOrbitTree(solar, detailsCard, prefix, failures);
            var charts = Descendants(solar).Where(e => e.GetType().Name == "OrbitSystemChart").ToArray();
            if (charts.Length != (progress ? 1 : 0)) failures.Add(prefix + ": must have one shared chart or none");
            if (progress)
            {
                var metrics = (System.Collections.IEnumerable)Get(charts[0], "Metrics")!;
                var bodies = metrics.Cast<object>().Select(m => Get(m, "Body")!.ToString());
                if (string.Join(",", bodies) != "Venus,Earth,Mars,Jupiter,Saturn")
                    failures.Add(prefix + ": shared orbit order/mapping");
                if (variant == "both")
                {
                    var expected = new Dictionary<string, (string Label, string Value)>
                    {
                        ["Venus"] = ("Fable", "63%"), ["Earth"] = ("주간", "24%"),
                        ["Mars"] = ("5시간", "8%"), ["Jupiter"] = ("5시간", "0%"), ["Saturn"] = ("주간", "36%")
                    };
                    foreach (var metric in metrics.Cast<object>())
                    {
                        var expectedMetric = expected[Get(metric, "Body")!.ToString()!];
                        if (Get<string>(metric, "Label") != expectedMetric.Label || Get<string>(metric, "ValueText") != expectedMetric.Value)
                            failures.Add(prefix + ": reordering changed a planet's label/value");
                    }
                }
            }
            if (preview is not null && variant == "both" && progress && rows == "SingleRow")
            {
                RenderOrbit(card, Path.Combine(preview, $"widget-{(light ? "light" : "dark")}-{density}.png"));
                if (density == "Comfortable") RenderOrbit(detailsCard, Path.Combine(preview, $"details-{(light ? "light" : "dark")}.png"));
            }
            // Theme changes on the same window must restore the old layout and back again.
            Option("WidgetTheme", "Modern");
            windowType.GetMethod("ApplySettings", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(widget, [settings]);
            if (RequiredElement<Grid>(widget, "OrbitClaudeSystem").Parent is not StackPanel { Visibility: Visibility.Collapsed })
                failures.Add(prefix + ": orbit panel survived theme change");
            detailsType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(details, [state, settings]);
            if (RequiredElement<FrameworkElement>(details, "SolarSystem").Visibility != Visibility.Collapsed ||
                RequiredElement<FrameworkElement>(details, "ClaudeCard").Visibility != Visibility.Visible)
                failures.Add(prefix + ": details did not restore the non-Orbit layout");
            CloseWidget(widget);
            details.Close();
            cases++;
        }
        var metricType = RequiredType(assembly, "ClaudeUsageTray.OrbitMetric");
        var limitType = RequiredType(assembly, "ClaudeUsageTray.UsageLimit");
        var body = Enum.Parse(RequiredType(assembly, "ClaudeUsageTray.OrbitBodyKind"), "Moon");
        foreach (var value in new[] { -20d, 0d, 50d, 100d, 130d, double.NaN, double.PositiveInfinity })
        {
            var limit = Activator.CreateInstance(limitType, [value, null]);
            var metric = Activator.CreateInstance(metricType, ["test", body, limit, null, null])!;
            var normalized = Get(metric, "Value");
            var expected = double.IsFinite(value) ? (double?)Math.Clamp(value, 0, 100) : null;
            if (!Equals(normalized, expected)) failures.Add($"Normalization: {value}");
        }
        // Fable unavailable and expired are intentionally different states.
        var claudeMetrics = metricType.GetMethod("Claude", BindingFlags.Static | BindingFlags.NonPublic)!;
        foreach (var source in new[] { "ClaudeDesktop", "ClaudeCode" })
        foreach (var expired in new[] { false, true })
        {
            var state = factory.Create(true, true);
            var snapshot = Get(state, "Snapshot")!;
            snapshot.GetType().GetProperty("Fable")!.SetValue(snapshot, null);
            Set(snapshot.GetType(), snapshot, "Source",
                Enum.Parse(RequiredType(assembly, "ClaudeUsageTray.ClaudeUsageSource"), source));
            Set(snapshot.GetType(), snapshot, "FableExpired", expired);
            var metrics = (Array)claudeMetrics.Invoke(null, [state])!;
            var text = Get<string>(metrics.GetValue(2)!, "ValueText");
            var expected = source == "ClaudeDesktop" || !expired ? "미제공" : "--%";
            if (text != expected) failures.Add("Fable " + source + "/" + expired);
        }
        var position = RequiredType(assembly, "ClaudeUsageTray.OrbitSystemChart")
            .GetMethod("Position", BindingFlags.Static | BindingFlags.NonPublic)!;
        foreach (var sample in new[] { (0d, new Point(0, -10)), (25d, new Point(10, 0)),
                     (50d, new Point(0, 10)), (100d, new Point(0, -10)) })
        {
            var actual = (Point)position.Invoke(null, [new Point(), 10d, sample.Item1])!;
            if ((actual - sample.Item2).Length > 0.001) failures.Add("Orbit endpoint " + sample.Item1);
        }
        foreach (var failure in failures) Console.Error.WriteLine("ORBIT " + failure);
        Console.WriteLine($"Orbit systems: {cases} widget/detail states, 7 boundary values, 4 Fable states, 4 endpoint checks, {failures.Count} failures");
        return failures.Count + RunSolarDetailsProbe(assembly, factory);
    }

    private static IEnumerable<FrameworkElement> Descendants(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is FrameworkElement e && e.Visibility != Visibility.Visible) continue;
            if (child is FrameworkElement element) yield return element;
            foreach (var nested in Descendants(child)) yield return nested;
        }
    }

    private static void CheckOrbitTree(FrameworkElement system, FrameworkElement card, string prefix, List<string> failures)
    {
        foreach (var element in Descendants(system).Prepend(system))
        {
            var point = element.TranslatePoint(new Point(), card);
            if (point.X < -0.5 || point.Y < -0.5 || point.X + element.ActualWidth > card.ActualWidth + 0.5 ||
                point.Y + element.ActualHeight > card.ActualHeight + 0.5)
                failures.Add(prefix + ": out of card " + element.GetType().Name);
            if (element is TextBlock text && text.TextWrapping == TextWrapping.NoWrap && text.TextTrimming == TextTrimming.None)
            {
                var measured = new FormattedText(text.Text, System.Globalization.CultureInfo.CurrentCulture,
                    text.FlowDirection, new Typeface(text.FontFamily, text.FontStyle, text.FontWeight, text.FontStretch),
                    text.FontSize, text.Foreground, null, TextOptions.GetTextFormattingMode(text), VisualTreeHelper.GetDpi(text).PixelsPerDip);
                if (measured.Width > text.ActualWidth + 1) failures.Add(prefix + ": clipped text " + text.Text);
            }
        }
    }

    private static void RenderOrbit(FrameworkElement element, string path)
    {
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(element.ActualWidth * 2),
            (int)Math.Ceiling(element.ActualHeight * 2), 192, 192, PixelFormats.Pbgra32);
        bitmap.Render(element);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var file = File.Create(path);
        encoder.Save(file);
    }
}
