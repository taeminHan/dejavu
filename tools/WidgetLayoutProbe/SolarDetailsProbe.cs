using System.Reflection;
using System.Windows;
using System.Windows.Controls;

internal static partial class Program
{
    private static int RunSolarDetailsProbe(Assembly assembly, StateFactory factory)
    {
        var failures = new List<string>();
        var count = 0;
        var settingsType = RequiredType(assembly, "ClaudeUsageTray.TraySettings");
        var detailsType = RequiredType(assembly, "ClaudeUsageTray.UsageDetailsWindow");
        var statusType = RequiredType(assembly, "ClaudeUsageTray.UsageStatus");
        var apply = RequiredType(assembly, "ClaudeUsageTray.ThemeManager").GetMethod("Apply")!;
        var update = detailsType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)!;
        foreach (var light in new[] { false, true })
        foreach (var progress in new[] { true, false })
        foreach (var service in new (string Mode, bool Claude, bool Codex, bool ShowClaude, bool ShowCodex)[]
                 {
                     (Mode: "ClaudeOnly", Claude: true, Codex: false, ShowClaude: true, ShowCodex: false),
                     ("CodexOnly", false, true, false, true), ("ClaudeAndCodex", true, true, true, true),
                     ("AutoDetect", false, false, false, false), ("AutoDetect", true, false, true, false),
                     ("AutoDetect", false, true, false, true), ("AutoDetect", true, true, true, true),
                     ("ClaudeAndCodex", false, false, true, true), ("ClaudeOnly", false, false, true, false)
                 })
        foreach (var status in new[] { "Ready", "Loading", "LoginRequired", "RateLimited", "Offline", "Error" })
        {
            var settings = Activator.CreateInstance(settingsType)!;
            void Option(string property, string value) => Set(settingsType, settings, property,
                Enum.Parse(settingsType.GetProperty(property)!.PropertyType, value));
            Option("WidgetTheme", "Orbit");
            Option("Theme", light ? "Light" : "Dark");
            Option("ServiceDisplayMode", service.Mode);
            Set(settingsType, settings, "ShowProgressBars", progress);
            apply.Invoke(null, [settings]);
            var state = factory.Create(service.Claude, service.Codex);
            Set(state.GetType(), state, "Status", Enum.Parse(statusType, status));
            // A Ready provider without a snapshot is intentionally auto-detected;
            // keep unavailable providers Loading to exercise the no-provider case.
            Set(state.GetType(), state, "ClaudeStatus", Enum.Parse(statusType, service.Claude ? status : "Loading"));
            Set(state.GetType(), state, "CodexStatus", Enum.Parse(statusType, service.Codex ? status : "Loading"));
            Set(state.GetType(), state, "Message", "Claude Desktop 기록 · Codex 확인 실패 · 자동 재시도");
            Set(state.GetType(), state, "ClaudeMessage", "Claude Desktop 기록 12:54 · 다음 사용량 확인 대기");
            Set(state.GetType(), state, "CodexMessage", "Codex 확인 실패 · 자동 재시도");
            var details = (Window)Activator.CreateInstance(detailsType, nonPublic: true)!;
            update.Invoke(details, [state, settings]);
            var root = RequiredElement<FrameworkElement>(details, "DetailsCard");
            root.Measure(new Size(details.Width, double.PositiveInfinity));
            var naturalHeight = root.DesiredSize.Height;
            root.Arrange(new Rect(0, 0, details.Width, naturalHeight));
            root.UpdateLayout();
            var solar = RequiredElement<FrameworkElement>(details, "SolarSystem");
            var prefix = $"{light}/{progress}/{service}/{status}";
            if (solar.Visibility == Visibility.Visible)
                CheckOrbitTree(solar, root, prefix, failures);
            var charts = solar.Visibility == Visibility.Visible
                ? Descendants(solar).Where(e => e.GetType().Name == "OrbitSystemChart").ToArray() : [];
            var expectedTracks = (service.ShowClaude ? 3 : 0) + (service.ShowCodex ? 2 : 0);
            if (charts.Length != (progress && expectedTracks > 0 ? 1 : 0)) failures.Add(prefix + ": chart count");
            if (charts.Length == 1 && ((System.Collections.IEnumerable)Get(charts[0], "Metrics")!).Cast<object>().Count() != expectedTracks)
                failures.Add(prefix + ": hidden provider left tracks");
            if (charts.Length == 1)
            {
                var expectedBodies = new List<string>();
                if (service.ShowClaude) expectedBodies.AddRange(["Venus", "Earth", "Mars"]);
                if (service.ShowCodex) expectedBodies.AddRange(["Jupiter", "Saturn"]);
                var actualBodies = ((System.Collections.IEnumerable)Get(charts[0], "Metrics")!).Cast<object>()
                    .Select(metric => Get(metric, "Body")!.ToString());
                if (!actualBodies.SequenceEqual(expectedBodies)) failures.Add(prefix + ": solar orbit order");
            }
            var texts = Descendants(solar).OfType<TextBlock>().Select(t => t.Text).ToArray();
            if (solar.Visibility == Visibility.Visible && texts.Contains("초기화권") != service.ShowCodex)
                failures.Add(prefix + ": credit ownership");
            if ((solar.Visibility == Visibility.Visible) != (expectedTracks > 0)) failures.Add(prefix + ": empty state");
            var content = solar is Border { Child: StackPanel stack } ? stack.Children.OfType<Grid>().LastOrDefault() : null;
            if (expectedTracks > 0 && content?.ColumnDefinitions.Count != (service.ShowClaude && service.ShowCodex ? 3 : 1))
                failures.Add(prefix + ": hidden provider left a column");

            // Simulate a constrained work area without creating native windows.
            const double availableHeight = 380;
            root.Measure(new Size(details.Width, availableHeight));
            root.Arrange(new Rect(0, 0, details.Width, availableHeight));
            root.UpdateLayout();
            var scroll = RequiredElement<ScrollViewer>(details, "DetailsScroll");
            var footer = RequiredElement<FrameworkElement>(details, "DetailsFooter");
            var footerBottom = footer.TranslatePoint(new Point(0, footer.ActualHeight), root).Y;
            if (footerBottom > availableHeight + 0.5) failures.Add(prefix + ": footer clipped");
            if (naturalHeight > availableHeight && scroll.ScrollableHeight <= 0) failures.Add(prefix + ": overflow cannot scroll");
            scroll.ScrollToEnd();
            root.UpdateLayout();

            Option("WidgetTheme", "Modern");
            update.Invoke(details, [state, settings]);
            if (solar.Visibility != Visibility.Collapsed || details.Width != 420) failures.Add(prefix + ": theme restoration");
            details.Close();
            count++;
        }
        foreach (var failure in failures) Console.Error.WriteLine("SOLAR " + failure);
        Console.WriteLine($"Solar details: {count} provider/status/scroll states, {failures.Count} failures");
        return failures.Count;
    }
}
