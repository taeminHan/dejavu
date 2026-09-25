using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shell;
using System.Windows.Threading;

internal static class Program
{
    private const double HeightTolerance = 0.5;
    private const double IdentityTolerance = 0.01;
    private static readonly string[] GeometryElementNames =
    [
        "SmallPanel", "SmallProviderPanel", "SmallClaudePanel", "SmallCodexPanel",
        "CompactPanel", "CompactFiveCard", "CompactWeeklyCard", "CompactFableCard", "CompactCodexCard",
        "CompactFiveHourBar", "CompactWeeklyBar", "CompactFableBar", "CompactCodexBar",
        "ComfortablePanel", "ComfortableCodexCard", "CodexPanel", "CodexBar", "MetricsPanel",
        "ComfortableFiveCard", "ComfortableWeeklyCard", "ComfortableFableCard",
        "FiveHourBar", "WeeklyBar", "FableBar", "CompactMessagePanel"
    ];
    // In-taskbar docking uses its own geometry. The dock rectangle is arbitrary device-pixel
    // space; only the band height changes between cases.
    private const double TaskbarProgressMinimumBand = 38;
    private const int TaskbarBandLeftPixels = 0;
    private const int TaskbarBandTopPixels = 2000;
    private const int TaskbarBandRightPixels = 3840;
    private const int TaskbarAnchorRightPixels = 3600;
    private static readonly int[] TaskbarBandHeights = [32, 40, 48];
    private static readonly string[] TaskbarLinearPanelNames =
    [
        "SmallPanel", "CompactPanel", "ComfortablePanel", "CompactMessagePanel", "ThemeTextureOverlay"
    ];
    private static readonly TaskbarCellNames[] TaskbarCells =
    [
        new("TaskbarFiveCell", "TaskbarFiveHourLabel", "TaskbarFiveHourValue", "TaskbarFiveHourBar"),
        new("TaskbarWeeklyCell", "TaskbarWeeklyLabel", "TaskbarWeeklyValue", "TaskbarWeeklyBar"),
        new("TaskbarFableCell", "TaskbarFableLabel", "TaskbarFableValue", "TaskbarFableBar"),
        new("TaskbarCodexPanel", "TaskbarCodexLabel", "TaskbarCodexValue", "TaskbarCodexBar"),
        new("TaskbarMessageCell", "TaskbarMessageLabel", "TaskbarMessageValue", null)
    ];
    private static readonly string[] TaskbarGeometryElementNames =
    [
        "TaskbarPanel", "TaskbarClaudePanel", "TaskbarFiveCell", "TaskbarWeeklyCell", "TaskbarFableCell",
        "TaskbarCodexPanel", "TaskbarMessageCell",
        "TaskbarFiveHourLabel", "TaskbarFiveHourValue", "TaskbarFiveHourBar",
        "TaskbarWeeklyLabel", "TaskbarWeeklyValue", "TaskbarWeeklyBar",
        "TaskbarFableLabel", "TaskbarFableValue", "TaskbarFableBar",
        "TaskbarCodexLabel", "TaskbarCodexValue", "TaskbarCodexBar",
        "TaskbarMessageLabel", "TaskbarMessageValue"
    ];

    [STAThread]
    private static int Main()
    {
        var assembly = Assembly.Load("dejavu");
        var application = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        application.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new Uri("/dejavu;component/ThemeResources.xaml", UriKind.Relative)
        });

        var settingsType = RequiredType(assembly, "ClaudeUsageTray.TraySettings");
        var themeType = RequiredType(assembly, "ClaudeUsageTray.WidgetVisualTheme");
        var densityType = RequiredType(assembly, "ClaudeUsageTray.WidgetDensity");
        var layoutType = RequiredType(assembly, "ClaudeUsageTray.WidgetLayout");
        var serviceType = RequiredType(assembly, "ClaudeUsageTray.ServiceDisplayMode");
        var preferenceType = RequiredType(assembly, "ClaudeUsageTray.ThemePreference");
        var statusType = RequiredType(assembly, "ClaudeUsageTray.UsageStatus");
        var limitType = RequiredType(assembly, "ClaudeUsageTray.UsageLimit");
        var snapshotType = RequiredType(assembly, "ClaudeUsageTray.UsageSnapshot");
        var sourceType = RequiredType(assembly, "ClaudeUsageTray.ClaudeUsageSource");
        var codexSnapshotType = RequiredType(assembly, "ClaudeUsageTray.CodexUsageSnapshot");
        var stateType = RequiredType(assembly, "ClaudeUsageTray.ApplicationState");
        var themeManagerType = RequiredType(assembly, "ClaudeUsageTray.ThemeManager");
        var windowType = RequiredType(assembly, "ClaudeUsageTray.UsageWidgetWindow");
        var settingsWindowType = RequiredType(assembly, "ClaudeUsageTray.SettingsWindow");
        var applyTheme = themeManagerType.GetMethod("Apply", BindingFlags.Static | BindingFlags.Public)
                         ?? throw new MissingMethodException("ThemeManager.Apply");
        var constructor = windowType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
                              binder: null, [settingsType], modifiers: null)
                          ?? throw new MissingMethodException("UsageWidgetWindow(TraySettings)");
        var updateState = windowType.GetMethod("UpdateState", BindingFlags.Instance | BindingFlags.NonPublic)
                          ?? throw new MissingMethodException("UsageWidgetWindow.UpdateState");
        var settingsConstructor = settingsWindowType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
                                      binder: null, [settingsType], modifiers: null)
                                  ?? throw new MissingMethodException("SettingsWindow(TraySettings)");
        var updateFrame = settingsWindowType.GetMethod("UpdateWindowFrameAppearance",
                              BindingFlags.Instance | BindingFlags.NonPublic,
                              binder: null, Type.EmptyTypes, modifiers: null)
                          ?? throw new MissingMethodException("SettingsWindow.UpdateWindowFrameAppearance");
        var stateFactory = new StateFactory(statusType, limitType, snapshotType, sourceType, codexSnapshotType,
            stateType);
        var services = new[]
        {
            new ServiceScenario("ClaudeOnly", "ClaudeOnly", true, false),
            new ServiceScenario("CodexOnly", "CodexOnly", false, true),
            new ServiceScenario("ClaudeAndCodex", "ClaudeAndCodex", true, true),
            new ServiceScenario("AutoNone", "AutoDetect", false, false),
            new ServiceScenario("AutoClaude", "AutoDetect", true, false),
            new ServiceScenario("AutoCodex", "AutoDetect", false, true),
            new ServiceScenario("AutoBoth", "AutoDetect", true, true)
        };

        var clippingFailures = new List<string>();
        var layoutFailures = new List<string>();
        var snapshots = new Dictionary<string, LayoutSnapshot>();
        var count = 0;
        foreach (var progress in new[] { false, true })
        foreach (var theme in Enum.GetNames(themeType))
        foreach (var density in Enum.GetNames(densityType))
        foreach (var layout in Enum.GetNames(layoutType))
        foreach (var service in services)
        {
            var settings = Activator.CreateInstance(settingsType)
                           ?? throw new InvalidOperationException("Cannot create TraySettings");
            Set(settingsType, settings, "ShowProgressBars", progress);
            Set(settingsType, settings, "WidgetTheme", Enum.Parse(themeType, theme));
            Set(settingsType, settings, "WidgetDensity", Enum.Parse(densityType, density));
            Set(settingsType, settings, "WidgetLayout", Enum.Parse(layoutType, layout));
            Set(settingsType, settings, "ServiceDisplayMode", Enum.Parse(serviceType, service.Mode));
            Set(settingsType, settings, "Theme", Enum.Parse(preferenceType, "Dark"));
            applyTheme.Invoke(null, [settings]);

            var window = (Window)constructor.Invoke([settings]);
            updateState.Invoke(window, [stateFactory.Create(service.ShowClaude, service.ShowCodex)]);
            var card = (FrameworkElement)(window.FindName("WidgetCard")
                       ?? throw new InvalidOperationException("WidgetCard missing"));
            card.Measure(new Size(window.Width, double.PositiveInfinity));
            var desired = card.DesiredSize.Height;
            if (desired > window.Height + HeightTolerance)
            {
                clippingFailures.Add($"theme={theme}, density={density}, layout={layout}, service={service.Name}, " +
                             $"progress={progress}: desired={desired:0.##}, window={window.Height:0.##}, " +
                             $"deficit={desired - window.Height:0.##}");
            }
            card.Arrange(new Rect(0, 0, window.Width, window.Height));
            card.UpdateLayout();
            snapshots[Key(progress, theme, density, layout, service.Name)] = new LayoutSnapshot(
                window.Width,
                window.Height,
                desired,
                CaptureGeometry(window, card));
            count++;
            CloseWidget(window);
        }

        var invariantCount = 0;
        foreach (var progress in new[] { false, true })
        foreach (var theme in Enum.GetNames(themeType))
        foreach (var density in Enum.GetNames(densityType))
        foreach (var service in new[] { "ClaudeOnly", "CodexOnly", "AutoNone", "AutoClaude", "AutoCodex" })
        {
            var single = snapshots[Key(progress, theme, density, "SingleRow", service)];
            var twoRows = snapshots[Key(progress, theme, density, "TwoRows", service)];
            if (!single.IsEquivalentTo(twoRows))
            {
                layoutFailures.Add($"theme={theme}, density={density}, service={service}, progress={progress}: " +
                                   $"single={single}, twoRows={twoRows}");
            }
            invariantCount++;
        }

        var splitCount = 0;
        foreach (var progress in new[] { false, true })
        foreach (var theme in Enum.GetNames(themeType))
        foreach (var density in Enum.GetNames(densityType))
        foreach (var service in new[] { "ClaudeAndCodex", "AutoBoth" })
        {
            var single = snapshots[Key(progress, theme, density, "SingleRow", service)];
            var twoRows = snapshots[Key(progress, theme, density, "TwoRows", service)];
            if (!single.HasExpectedProviderSplit(twoRows, density == "Small"))
            {
                layoutFailures.Add($"theme={theme}, density={density}, service={service}, progress={progress}: " +
                                   $"single={single}, twoRows={twoRows}");
            }
            splitCount++;
        }

        var autoDetectCount = 0;
        foreach (var progress in new[] { false, true })
        foreach (var theme in Enum.GetNames(themeType))
        foreach (var density in Enum.GetNames(densityType))
        foreach (var layout in Enum.GetNames(layoutType))
        foreach (var pair in new[]
                 {
                     (Forced: "ClaudeOnly", Auto: "AutoClaude"),
                     (Forced: "CodexOnly", Auto: "AutoCodex"),
                     (Forced: "ClaudeAndCodex", Auto: "AutoBoth")
                 })
        {
            var forced = snapshots[Key(progress, theme, density, layout, pair.Forced)];
            var detected = snapshots[Key(progress, theme, density, layout, pair.Auto)];
            if (!forced.IsEquivalentTo(detected))
            {
                layoutFailures.Add($"theme={theme}, density={density}, layout={layout}, " +
                                   $"service={pair.Auto}, progress={progress}: forced={forced}, auto={detected}");
            }
            autoDetectCount++;
        }

        var frameFailures = new List<string>();
        var frameStateCount = 0;
        foreach (var preference in new[] { "Dark", "Light" })
        foreach (var theme in Enum.GetNames(themeType))
        {
            var settings = Activator.CreateInstance(settingsType)
                           ?? throw new InvalidOperationException("Cannot create TraySettings");
            Set(settingsType, settings, "WidgetTheme", Enum.Parse(themeType, theme));
            Set(settingsType, settings, "Theme", Enum.Parse(preferenceType, preference));
            applyTheme.Invoke(null, [settings]);

            var settingsWindow = (Window)settingsConstructor.Invoke([settings]);
            updateFrame.Invoke(settingsWindow, null);
            VerifySettingsFrame(settingsWindow, theme, preference, maximized: false, frameFailures);
            frameStateCount++;

            settingsWindow.WindowState = WindowState.Maximized;
            updateFrame.Invoke(settingsWindow, null);
            VerifySettingsFrame(settingsWindow, theme, preference, maximized: true, frameFailures);
            frameStateCount++;
            (settingsWindowType.GetProperty("AllowClose", BindingFlags.Instance | BindingFlags.Public |
                                             BindingFlags.NonPublic)
             ?? throw new MissingMemberException(settingsWindowType.FullName, "AllowClose"))
                .SetValue(settingsWindow, true);
            settingsWindow.Close();
        }

        // Taskbar docking ignores density, row layout and visual theme. Every combination of those
        // axes must therefore produce the same geometry for one (progress, service, band) triple.
        var placementType = RequiredType(assembly, "ClaudeUsageTray.WidgetPlacement");
        var inTaskbar = Enum.Parse(placementType, "InTaskbar");
        var taskbarProbe = new TaskbarProbe(assembly, windowType);
        var taskbarClipping = new List<string>();
        var taskbarOverBand = new List<string>();
        var taskbarMismatches = new List<string>();
        var taskbarSnapshots = new Dictionary<string, LayoutSnapshot>();
        var taskbarReferences = new Dictionary<string, (LayoutSnapshot Snapshot, string Description)>();
        var taskbarCount = 0;
        foreach (var progress in new[] { false, true })
        foreach (var theme in Enum.GetNames(themeType))
        foreach (var density in Enum.GetNames(densityType))
        foreach (var layout in Enum.GetNames(layoutType))
        foreach (var service in services)
        foreach (var band in TaskbarBandHeights)
        {
            var settings = Activator.CreateInstance(settingsType)
                           ?? throw new InvalidOperationException("Cannot create TraySettings");
            Set(settingsType, settings, "ShowProgressBars", progress);
            Set(settingsType, settings, "WidgetTheme", Enum.Parse(themeType, theme));
            Set(settingsType, settings, "WidgetDensity", Enum.Parse(densityType, density));
            Set(settingsType, settings, "WidgetLayout", Enum.Parse(layoutType, layout));
            Set(settingsType, settings, "ServiceDisplayMode", Enum.Parse(serviceType, service.Mode));
            Set(settingsType, settings, "Theme", Enum.Parse(preferenceType, "Dark"));
            Set(settingsType, settings, "WidgetPlacement", inTaskbar);
            applyTheme.Invoke(null, [settings]);

            var window = (Window)constructor.Invoke([settings]);
            var dpi = VisualTreeHelper.GetDpi(window);
            var bandPixels = (int)Math.Round(band * dpi.DpiScaleY);
            taskbarProbe.Dock(window, bandPixels);
            updateState.Invoke(window, [stateFactory.Create(service.ShowClaude, service.ShowCodex)]);
            taskbarProbe.PositionFromSettings(window);
            var card = RequiredElement<FrameworkElement>(window, "WidgetCard");
            card.Measure(new Size(window.Width, double.PositiveInfinity));
            var desired = card.DesiredSize.Height;
            card.Arrange(new Rect(0, 0, window.Width, window.Height));
            card.UpdateLayout();

            var prefix = $"theme={theme}, density={density}, layout={layout}, service={service.Name}, " +
                         $"progress={progress}, band={band}";
            var snapshot = new LayoutSnapshot(window.Width, window.Height, desired,
                CaptureTaskbarGeometry(window, card));
            taskbarSnapshots[TaskbarKey(progress, theme, density, layout, service.Name, band)] = snapshot;
            var referenceKey = $"{progress}|{service.Name}|{band}";
            if (taskbarReferences.TryGetValue(referenceKey, out var reference))
            {
                if (!snapshot.IsEquivalentTo(reference.Snapshot))
                {
                    taskbarMismatches.Add($"{prefix}: {snapshot} differs from {reference.Description} " +
                                          $"({reference.Snapshot}) at {FirstDifference(snapshot, reference.Snapshot)}");
                }
            }
            else taskbarReferences[referenceKey] = (snapshot, $"theme={theme}, density={density}, layout={layout}");

            if (!Get<bool>(window, "IsTaskbarDocked"))
                taskbarMismatches.Add($"{prefix}: widget is not docked after SetTaskbarDock");
            if (desired > window.Height + HeightTolerance)
            {
                taskbarClipping.Add($"{prefix}: desired={desired:0.##}, window={window.Height:0.##}, " +
                                    $"deficit={desired - window.Height:0.##}");
            }

            // WPF sizes the HWND rounding halves up, as PositionInTaskbar predicts.
            var heightPixels = Math.Round(window.Height * dpi.DpiScaleY, MidpointRounding.AwayFromZero);
            var topPixels = window.Top * dpi.DpiScaleY;
            if (heightPixels > bandPixels || double.IsNaN(topPixels) ||
                topPixels < TaskbarBandTopPixels - HeightTolerance ||
                topPixels + heightPixels > TaskbarBandTopPixels + bandPixels + HeightTolerance)
            {
                taskbarOverBand.Add($"{prefix}: window {heightPixels:0}px at y={topPixels:0.#} leaves the " +
                                    $"{bandPixels}px band at y={TaskbarBandTopPixels}");
            }
            var rightPixels = (window.Left + window.Width) * dpi.DpiScaleX;
            if (double.IsNaN(rightPixels) || rightPixels > TaskbarAnchorRightPixels + HeightTolerance)
                taskbarMismatches.Add($"{prefix}: right edge {rightPixels:0.#}px passes the anchor " +
                                      $"{TaskbarAnchorRightPixels}px");

            foreach (var name in TaskbarLinearPanelNames)
            {
                if (RequiredElement<UIElement>(window, name).Visibility == Visibility.Visible)
                    taskbarMismatches.Add($"{prefix}: {name} is visible while docked");
            }
            ExpectVisibility(window, "TaskbarPanel", true, prefix, taskbarMismatches);
            ExpectVisibility(window, "TaskbarClaudePanel", service.ShowClaude, prefix, taskbarMismatches);
            ExpectVisibility(window, "TaskbarCodexPanel", service.ShowCodex, prefix, taskbarMismatches);
            ExpectVisibility(window, "TaskbarMessageCell", !service.ShowClaude && !service.ShowCodex, prefix,
                taskbarMismatches);

            var visibleCells = TaskbarCells
                .Select(names => (Names: names, Element: RequiredElement<FrameworkElement>(window, names.Cell)))
                .Where(cell => IsEffectivelyVisible(cell.Element, card))
                .ToList();
            var expectedBars = progress && (service.ShowClaude || service.ShowCodex) &&
                               band >= TaskbarProgressMinimumBand;
            foreach (var cell in visibleCells)
            {
                if (cell.Names.Bar is null) continue;
                var bar = RequiredElement<ProgressBar>(window, cell.Names.Bar);
                var barVisible = bar.Visibility == Visibility.Visible;
                if (barVisible != expectedBars)
                    taskbarMismatches.Add($"{prefix}: {cell.Names.Bar} visible={barVisible}, expected {expectedBars}");
                // Every visible provider has data here, so text and a shown bar must carry one clamped value.
                var value = RequiredElement<TextBlock>(window, cell.Names.Value);
                if (value.Text == "--%" || (barVisible && (bar.Value <= 0 || value.Text != $"{bar.Value:0}%")))
                    taskbarMismatches.Add($"{prefix}: {cell.Names.Value} '{value.Text}' disagrees with " +
                                          $"{cell.Names.Bar} value {bar.Value:0.##}");
            }

            var metrics = taskbarProbe.Calculate(Enum.Parse(densityType, density), Enum.Parse(layoutType, layout),
                Enum.Parse(themeType, theme), service.ShowClaude, service.ShowCodex, progress,
                bandPixels / dpi.DpiScaleY);
            if (Get(metrics, "Taskbar") is not { } taskbarMetrics)
            {
                taskbarMismatches.Add($"{prefix}: WidgetLayoutCalculator returned no taskbar metrics");
            }
            else
            {
                var expectedWidth = Get<double>(metrics, "Width");
                var expectedHeight = Get<double>(metrics, "Height");
                if (Math.Abs(window.Width - expectedWidth) > HeightTolerance ||
                    Math.Abs(window.Height - expectedHeight) > HeightTolerance)
                {
                    taskbarMismatches.Add($"{prefix}: window {window.Width:0.##}x{window.Height:0.##} != " +
                                          $"calculator {expectedWidth:0.##}x{expectedHeight:0.##}");
                }
                if (Get<bool>(taskbarMetrics, "ProgressVisible") != expectedBars)
                    taskbarMismatches.Add($"{prefix}: calculator ProgressVisible != {expectedBars}");

                // Hidden providers must leave no gap: the visible cells span exactly the padded card.
                var paddingX = Get<double>(taskbarMetrics, "PaddingX");
                var pixelExact = new[]
                    {
                        paddingX, Get<double>(taskbarMetrics, "CellWidth"),
                        Get<double>(taskbarMetrics, "CellGap"), Get<double>(taskbarMetrics, "ProviderGap")
                    }
                    .All(length => IsWholePixel(length * dpi.DpiScaleX));
                // Layout rounding may move each fractional-pixel cell by one device pixel.
                var edgeTolerance = pixelExact
                    ? HeightTolerance
                    : HeightTolerance + visibleCells.Count / dpi.DpiScaleX;
                if (visibleCells.Count == 0)
                {
                    taskbarMismatches.Add($"{prefix}: no taskbar cell is visible");
                }
                else
                {
                    var bounds = visibleCells.Select(cell => BoundsIn(cell.Element, card)).ToList();
                    var left = bounds.Min(rect => rect.Left);
                    var right = bounds.Max(rect => rect.Right);
                    if (Math.Abs(left - paddingX) > edgeTolerance ||
                        Math.Abs(right - (window.Width - paddingX)) > edgeTolerance)
                    {
                        taskbarMismatches.Add($"{prefix}: cells span {left:0.##}..{right:0.##}, expected " +
                                              $"{paddingX:0.##}..{window.Width - paddingX:0.##}");
                    }
                }
            }

            // Text measurement invalidates the arranged tree, so it runs after every geometry check.
            foreach (var cell in visibleCells)
            {
                var cellWidth = cell.Element.RenderSize.Width;
                foreach (var (name, sample) in new (string Name, string? Sample)[]
                         {
                             (cell.Names.Label, null), (cell.Names.Value, null), (cell.Names.Value, "100%")
                         })
                {
                    var text = RequiredElement<TextBlock>(window, name);
                    if (text.Visibility != Visibility.Visible) continue;
                    var naturalWidth = NaturalWidth(text, sample);
                    if (naturalWidth > cellWidth + HeightTolerance)
                    {
                        taskbarClipping.Add($"{prefix}: {name} '{sample ?? text.Text}' needs " +
                                            $"{naturalWidth:0.##}, cell={cellWidth:0.##}");
                    }
                }
            }
            taskbarCount++;
            CloseWidget(window);
        }

        foreach (var progress in new[] { false, true })
        foreach (var theme in Enum.GetNames(themeType))
        foreach (var density in Enum.GetNames(densityType))
        foreach (var layout in Enum.GetNames(layoutType))
        foreach (var band in TaskbarBandHeights)
        foreach (var pair in new[]
                 {
                     (Forced: "ClaudeOnly", Auto: "AutoClaude"),
                     (Forced: "CodexOnly", Auto: "AutoCodex"),
                     (Forced: "ClaudeAndCodex", Auto: "AutoBoth")
                 })
        {
            var forced = taskbarSnapshots[TaskbarKey(progress, theme, density, layout, pair.Forced, band)];
            var detected = taskbarSnapshots[TaskbarKey(progress, theme, density, layout, pair.Auto, band)];
            if (!forced.IsEquivalentTo(detected))
            {
                taskbarMismatches.Add($"theme={theme}, density={density}, layout={layout}, service={pair.Auto}, " +
                                      $"progress={progress}, band={band}: forced={forced}, auto={detected} " +
                                      $"at {FirstDifference(forced, detected)}");
            }
        }

        var tracker = new TrackerProbe(assembly);
        tracker.Run();
        tracker.Dispose();

        foreach (var failure in clippingFailures) Console.Error.WriteLine($"CLIP {failure}");
        foreach (var failure in layoutFailures) Console.Error.WriteLine($"LAYOUT {failure}");
        foreach (var failure in frameFailures) Console.Error.WriteLine($"FRAME {failure}");
        foreach (var failure in taskbarClipping) Console.Error.WriteLine($"TASKBAR CLIP {failure}");
        foreach (var failure in taskbarOverBand) Console.Error.WriteLine($"TASKBAR BAND {failure}");
        foreach (var failure in taskbarMismatches) Console.Error.WriteLine($"TASKBAR LAYOUT {failure}");
        foreach (var failure in tracker.Failures) Console.Error.WriteLine($"TRACKER {failure}");
        Console.WriteLine($"Widget layout matrix: {count} checked, {clippingFailures.Count} clipped, " +
                          $"{invariantCount} zero/one-provider invariants, {splitCount} two-provider splits, " +
                          $"{autoDetectCount} auto-detection equivalences, " +
                          $"{layoutFailures.Count} mismatched");
        Console.WriteLine($"Settings frame matrix: {frameStateCount} checked, {frameFailures.Count} invalid");
        Console.WriteLine($"Taskbar layout matrix: {taskbarCount} checked, {taskbarClipping.Count} clipped, " +
                          $"{taskbarOverBand.Count} over band, {taskbarMismatches.Count} mismatched");
        Console.WriteLine($"Taskbar tracker transitions: {tracker.Count} checked, {tracker.Failures.Count} mismatched");
        return clippingFailures.Count == 0 && layoutFailures.Count == 0 && frameFailures.Count == 0 &&
               taskbarClipping.Count == 0 && taskbarOverBand.Count == 0 && taskbarMismatches.Count == 0 &&
               tracker.Failures.Count == 0
            ? 0
            : 1;
    }

    // The widget cancels every close that is not an application shutdown.
    private static void CloseWidget(Window window)
    {
        (window.GetType().GetProperty("AllowClose", BindingFlags.Instance | BindingFlags.Public |
                                                    BindingFlags.NonPublic)
         ?? throw new MissingMemberException(window.GetType().FullName, "AllowClose"))
            .SetValue(window, true);
        window.Close();
    }

    private static string Key(bool progress, string theme, string density, string layout, string service) =>
        $"{progress}|{theme}|{density}|{layout}|{service}";

    private static T RequiredElement<T>(FrameworkElement window, string name) where T : class =>
        window.FindName(name) as T ?? throw new InvalidOperationException($"{name} missing");

    private static IReadOnlyDictionary<string, ElementSnapshot> CaptureGeometry(Window window, FrameworkElement card)
    {
        var result = new Dictionary<string, ElementSnapshot>(StringComparer.Ordinal);
        foreach (var name in GeometryElementNames)
        {
            var element = RequiredElement<FrameworkElement>(window, name);
            var visible = element.Visibility == Visibility.Visible;
            var bounds = visible
                ? new Rect(element.TranslatePoint(new Point(0, 0), card), element.RenderSize)
                : Rect.Empty;
            result[name] = new ElementSnapshot(element.Visibility, bounds);
        }
        return result;
    }

    private static void VerifySettingsFrame(Window window, string theme, string preference, bool maximized,
        ICollection<string> failures)
    {
        var state = maximized ? "Maximized" : "Normal";
        var prefix = $"theme={theme}, preference={preference}, state={state}";
        var surface = RequiredElement<Grid>(window, "WindowSurface");
        var shell = RequiredElement<Grid>(window, "SettingsShell");
        var frame = RequiredElement<Border>(window, "WindowFrame");
        var chrome = WindowChrome.GetWindowChrome(window);
        var resourceRadius = window.FindResource("WindowCornerRadius") is CornerRadius radius
            ? radius : new CornerRadius(0);
        var resourceThickness = window.FindResource("WindowFrameThickness") is Thickness thickness
            ? thickness : new Thickness(0);
        var frameThickness = Math.Max(
            Math.Max(resourceThickness.Left, resourceThickness.Top),
            Math.Max(resourceThickness.Right, resourceThickness.Bottom));
        var dpi = VisualTreeHelper.GetDpi(window);
        var scale = Math.Max(dpi.DpiScaleX, 1d);
        var strokePixels = Math.Round(frameThickness * scale);
        var nativeRadiusPixels = Math.Ceiling(resourceRadius.TopLeft * scale) / 2d;
        var insetPixels = maximized || nativeRadiusPixels <= 1d + (strokePixels / 2d)
            ? 0d
            : 1d;
        var expectedInset = insetPixels / scale;
        var expectedFrameRadius = maximized
            ? 0d
            : Math.Max(0d, (nativeRadiusPixels - insetPixels - (strokePixels / 2d)) / scale);
        var expectedRadius = new CornerRadius(expectedFrameRadius);
        var expectedThickness = maximized ? new Thickness(0) : resourceThickness;
        var expectedMargin = new Thickness(expectedInset);

        if (frame.Clip is not null) failures.Add($"{prefix}: outer frame owns a Clip");
        if (!ReferenceEquals(VisualTreeHelper.GetParent(frame), surface) ||
            surface.Children.IndexOf(frame) != surface.Children.Count - 1)
            failures.Add($"{prefix}: frame is not the last surface overlay");
        if (frame.IsHitTestVisible) failures.Add($"{prefix}: frame intercepts pointer input");
        if (frame.Background is not SolidColorBrush { Color.A: 0 })
            failures.Add($"{prefix}: frame background is not transparent");
        if (!window.UseLayoutRounding || !surface.UseLayoutRounding || !shell.UseLayoutRounding)
            failures.Add($"{prefix}: layout rounding is not enabled across the shell");
        if (!ThicknessEquals(frame.Margin, expectedMargin))
            failures.Add($"{prefix}: frame margin {frame.Margin} != {expectedMargin}");
        if (!CornerEquals(frame.CornerRadius, expectedRadius))
            failures.Add($"{prefix}: frame radius {frame.CornerRadius} != {expectedRadius}");
        if (!ThicknessEquals(frame.BorderThickness, expectedThickness))
            failures.Add($"{prefix}: frame thickness {frame.BorderThickness} != {expectedThickness}");
        if (chrome is null || !CornerEquals(chrome.CornerRadius, resourceRadius))
            failures.Add($"{prefix}: WindowChrome radius does not match the theme resource");
    }

    private static bool CornerEquals(CornerRadius left, CornerRadius right) =>
        NearlyEqual(left.TopLeft, right.TopLeft) && NearlyEqual(left.TopRight, right.TopRight) &&
        NearlyEqual(left.BottomRight, right.BottomRight) && NearlyEqual(left.BottomLeft, right.BottomLeft);

    private static bool ThicknessEquals(Thickness left, Thickness right) =>
        NearlyEqual(left.Left, right.Left) && NearlyEqual(left.Top, right.Top) &&
        NearlyEqual(left.Right, right.Right) && NearlyEqual(left.Bottom, right.Bottom);

    private static bool NearlyEqual(double left, double right) =>
        Math.Abs(left - right) <= IdentityTolerance;

    private static Type RequiredType(Assembly assembly, string name) =>
        assembly.GetType(name, throwOnError: true)!;

    private static void Set(Type type, object target, string name, object value) =>
        (type.GetProperty(name) ?? throw new MissingMemberException(type.FullName, name)).SetValue(target, value);

    private static object? Get(object target, string name) =>
        (target.GetType().GetProperty(name, BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
         ?? throw new MissingMemberException(target.GetType().FullName, name)).GetValue(target);

    private static T Get<T>(object target, string name) =>
        Get(target, name) is T value
            ? value
            : throw new InvalidOperationException($"{target.GetType().Name}.{name} is not {typeof(T).Name}");

    private static object CreateByName(Type type, IReadOnlyDictionary<string, object?> values)
    {
        var constructor = type.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            .Single(candidate => candidate.GetParameters().Length == values.Count);
        return constructor.Invoke(constructor.GetParameters()
            .Select(parameter => values.TryGetValue(parameter.Name ?? string.Empty, out var value)
                ? value
                : throw new MissingMemberException(type.FullName, parameter.Name))
            .ToArray());
    }

    private static string TaskbarKey(bool progress, string theme, string density, string layout, string service,
        int band) =>
        $"{Key(progress, theme, density, layout, service)}|{band}";

    private static IReadOnlyDictionary<string, ElementSnapshot> CaptureTaskbarGeometry(Window window,
        FrameworkElement card)
    {
        var result = new Dictionary<string, ElementSnapshot>(StringComparer.Ordinal);
        foreach (var name in TaskbarGeometryElementNames)
        {
            var element = RequiredElement<FrameworkElement>(window, name);
            var visible = IsEffectivelyVisible(element, card);
            result[name] = new ElementSnapshot(visible ? Visibility.Visible : Visibility.Collapsed,
                visible ? BoundsIn(element, card) : Rect.Empty);
        }
        return result;
    }

    private static bool IsEffectivelyVisible(DependencyObject element, DependencyObject root)
    {
        for (DependencyObject? current = element; current is not null; current = VisualTreeHelper.GetParent(current))
        {
            if (current is UIElement { Visibility: not Visibility.Visible }) return false;
            if (ReferenceEquals(current, root)) return true;
        }
        return false;
    }

    private static Rect BoundsIn(FrameworkElement element, FrameworkElement ancestor) =>
        new(element.TranslatePoint(new Point(0, 0), ancestor), element.RenderSize);

    private static void ExpectVisibility(FrameworkElement window, string name, bool visible, string prefix,
        ICollection<string> failures)
    {
        var actual = RequiredElement<UIElement>(window, name).Visibility;
        var expected = visible ? Visibility.Visible : Visibility.Collapsed;
        if (actual != expected) failures.Add($"{prefix}: {name} is {actual}, expected {expected}");
    }

    private static double NaturalWidth(TextBlock text, string? sample)
    {
        var original = text.Text;
        if (sample is not null) text.Text = sample;
        text.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var width = text.DesiredSize.Width;
        if (sample is not null) text.Text = original;
        return width;
    }

    private static bool IsWholePixel(double pixels) => Math.Abs(pixels - Math.Round(pixels)) <= IdentityTolerance;

    private static string FirstDifference(LayoutSnapshot left, LayoutSnapshot right) =>
        left.Elements
            .Where(pair => !right.Elements.TryGetValue(pair.Key, out var other) || !pair.Value.IsEquivalentTo(other))
            .Select(pair => $"{pair.Key} ({pair.Value.Visibility}, {pair.Value.Bounds})")
            .FirstOrDefault() ?? "window size";

    private sealed record ServiceScenario(string Name, string Mode, bool ShowClaude, bool ShowCodex);

    private sealed record TaskbarCellNames(string Cell, string Label, string Value, string? Bar);

    /// <summary>
    /// Reflection access to the internal taskbar docking surface. The probe never talks to Explorer:
    /// it feeds a synthetic device-pixel dock to the widget exactly as the controller would.
    /// </summary>
    private sealed class TaskbarProbe
    {
        private readonly Type _dockType;
        private readonly Type _requestType;
        private readonly MethodInfo _calculate;
        private readonly MethodInfo _setTaskbarDock;
        private readonly MethodInfo _positionFromSettings;

        internal TaskbarProbe(Assembly assembly, Type windowType)
        {
            _dockType = RequiredType(assembly, "ClaudeUsageTray.TaskbarDock");
            _requestType = RequiredType(assembly, "ClaudeUsageTray.WidgetLayoutRequest");
            var calculatorType = RequiredType(assembly, "ClaudeUsageTray.WidgetLayoutCalculator");
            _calculate = calculatorType.GetMethod("Calculate", BindingFlags.Static | BindingFlags.NonPublic,
                             binder: null, [_requestType], modifiers: null)
                         ?? throw new MissingMethodException("WidgetLayoutCalculator.Calculate");
            _setTaskbarDock = windowType.GetMethod("SetTaskbarDock", BindingFlags.Instance | BindingFlags.NonPublic,
                                  binder: null, [typeof(Nullable<>).MakeGenericType(_dockType)], modifiers: null)
                              ?? throw new MissingMethodException("UsageWidgetWindow.SetTaskbarDock(TaskbarDock?)");
            _positionFromSettings = windowType.GetMethod("PositionFromSettings",
                                        BindingFlags.Instance | BindingFlags.NonPublic,
                                        binder: null, [typeof(bool)], modifiers: null)
                                    ?? throw new MissingMethodException("UsageWidgetWindow.PositionFromSettings");
        }

        internal void Dock(Window window, int bandHeightPixels)
        {
            var dock = CreateByName(_dockType, new Dictionary<string, object?>
            {
                ["BandLeftPixels"] = TaskbarBandLeftPixels,
                ["BandTopPixels"] = TaskbarBandTopPixels,
                ["BandRightPixels"] = TaskbarBandRightPixels,
                ["BandBottomPixels"] = TaskbarBandTopPixels + bandHeightPixels,
                ["AnchorRightPixels"] = TaskbarAnchorRightPixels,
                ["LightTaskbar"] = false,
                ["HighContrast"] = false
            });
            _setTaskbarDock.Invoke(window, [dock]);
        }

        internal void PositionFromSettings(Window window) => _positionFromSettings.Invoke(window, [false]);

        internal object Calculate(object density, object layout, object theme, bool showClaude, bool showCodex,
            bool showProgressBars, double taskbarBandHeight) =>
            _calculate.Invoke(null, [CreateByName(_requestType, new Dictionary<string, object?>
            {
                ["Density"] = density,
                ["Layout"] = layout,
                ["Theme"] = theme,
                ["ShowClaude"] = showClaude,
                ["ShowCodex"] = showCodex,
                ["ShowProgressBars"] = showProgressBars,
                ["InTaskbar"] = true,
                ["TaskbarBandHeight"] = taskbarBandHeight
            })]) ?? throw new InvalidOperationException("WidgetLayoutCalculator.Calculate returned null");
    }

    /// <summary>
    /// Replays TaskbarTracker's settle rules with synthetic evaluations and TickCount64 readings. The
    /// tracker is constructed but never enabled, so no broadcast window, hook or timer starts and nothing
    /// talks to Explorer. Each timeline starts from the state BeginSettling leaves behind.
    /// </summary>
    private sealed class TrackerProbe : IDisposable
    {
        private const long Start = 1_000_000;
        private const string Settling = "Suppressed(settling) settling";
        private const string Fullscreen = "Suppressed(fullscreen)";
        private const string Docked = "Docked()";
        private static readonly string[] HardFallbackReasons =
            ["shell_mismatch", "non_xaml_taskbar", "vertical", "autohide", "rtl_or_mirrored", "band_too_small"];
        private static readonly string[] FallbackReasons =
            [.. HardFallbackReasons, "taskbar_missing", "tray_missing"];
        private readonly IDisposable _tracker;
        private readonly Type _dockType;
        private readonly Type _evaluationType;
        private readonly Type _statusType;
        private readonly MethodInfo _resolveState;
        private readonly MethodInfo _leavesFallback;
        private readonly MethodInfo _isHardFallback;
        private readonly FieldInfo _settling;
        private readonly FieldInfo _settleStartedAt;
        private readonly FieldInfo _settleSample;
        private readonly FieldInfo _settleFallbackReason;
        private readonly FieldInfo _settleFallbackSince;
        private readonly FieldInfo _autoHideQueryCompleted;
        private readonly List<string> _failures = [];

        internal TrackerProbe(Assembly assembly)
        {
            var trackerType = RequiredType(assembly, "ClaudeUsageTray.TaskbarTracker");
            _dockType = RequiredType(assembly, "ClaudeUsageTray.TaskbarDock");
            _statusType = RequiredType(assembly, "ClaudeUsageTray.TaskbarDockStatus");
            _evaluationType = trackerType.GetNestedType("Evaluation", BindingFlags.NonPublic)
                              ?? throw new TypeLoadException("TaskbarTracker.Evaluation");
            var constructor = trackerType.GetConstructor(BindingFlags.Instance | BindingFlags.NonPublic,
                                  binder: null, [typeof(Dispatcher)], modifiers: null)
                              ?? throw new MissingMethodException("TaskbarTracker(Dispatcher)");
            _tracker = (IDisposable)constructor.Invoke([Dispatcher.CurrentDispatcher]);
            _resolveState = trackerType.GetMethod("ResolveState", BindingFlags.Instance | BindingFlags.NonPublic,
                                binder: null, [_evaluationType, typeof(bool), typeof(long)], modifiers: null)
                            ?? throw new MissingMethodException("TaskbarTracker.ResolveState(Evaluation, bool, long)");
            _leavesFallback = trackerType.GetMethod("LeavesFallback", BindingFlags.Static | BindingFlags.NonPublic,
                                  binder: null, [_statusType, typeof(bool), _evaluationType], modifiers: null)
                              ?? throw new MissingMethodException("TaskbarTracker.LeavesFallback");
            _isHardFallback = trackerType.GetMethod("IsHardFallback", BindingFlags.Static | BindingFlags.NonPublic,
                                  binder: null, [typeof(string)], modifiers: null)
                              ?? throw new MissingMethodException("TaskbarTracker.IsHardFallback");
            _settling = Field(trackerType, "_settling");
            _settleStartedAt = Field(trackerType, "_settleStartedAt");
            _settleSample = Field(trackerType, "_settleSample");
            _settleFallbackReason = Field(trackerType, "_settleFallbackReason");
            _settleFallbackSince = Field(trackerType, "_settleFallbackSince");
            _autoHideQueryCompleted = Field(trackerType, "_autoHideQueryCompleted");
        }

        internal int Count { get; private set; }
        internal IReadOnlyList<string> Failures => _failures;

        internal void Run()
        {
            var a = Dock(0);
            var b = Dock(10);

            // A hard fallback ends settling only after repeating on the 250 ms samples for 2 s.
            foreach (var reason in HardFallbackReasons)
            {
                var scenario = $"{reason} confirmation";
                Begin(reason, null, autoHideCompleted: true);
                for (var offset = 250; offset <= 1750; offset += 250)
                    Expect(scenario, offset, Resolve(reason, null, true, offset), Settling);
                Expect(scenario, 2000, Resolve(reason, null, true, 2000), Fallback(reason));
            }

            // A different hard fallback restarts the 2 s confirmation.
            Begin("vertical", null, autoHideCompleted: true);
            Expect("reason change", 250, Resolve("vertical", null, true, 250), Settling);
            Expect("reason change", 500, Resolve("vertical", null, true, 500), Settling);
            for (var offset = 750; offset <= 2500; offset += 250)
                Expect("reason change", offset, Resolve("autohide", null, true, offset), Settling);
            Expect("reason change", 2750, Resolve("autohide", null, true, 2750), Fallback("autohide"));

            // Evaluations outside the cadence neither confirm nor reset a hard fallback.
            Begin("band_too_small", null, autoHideCompleted: true);
            foreach (var offset in new long[] { 2000, 5000, 9750 })
                Expect("non-sample fallback", offset, Resolve("band_too_small", null, false, offset), Settling);
            Expect("non-sample fallback", 10000, Resolve("band_too_small", null, false, 10000),
                Fallback("band_too_small"));
            Begin("band_too_small", null, autoHideCompleted: true);
            for (var offset = 250; offset <= 1750; offset += 250)
                Expect("mixed fallback", offset, Resolve("band_too_small", null, true, offset), Settling);
            Expect("mixed fallback", 2000, Resolve("band_too_small", null, false, 2000), Settling);
            Expect("mixed fallback", 2250, Resolve("band_too_small", null, true, 2250), Fallback("band_too_small"));

            // A missing taskbar or tray stays settling until 10 s after settling began.
            foreach (var reason in new[] { "taskbar_missing", "tray_missing" })
            {
                Begin(reason, null, autoHideCompleted: true);
                foreach (var offset in new long[] { 250, 2000, 2250, 5000, 9750 })
                    Expect(reason, offset, Resolve(reason, null, true, offset), Settling);
                Expect(reason, 10000, Resolve(reason, null, true, 10000), Fallback(reason));
            }

            // Two matching cadence samples dock once the auto-hide query finished or 2 s passed.
            Begin("", a, autoHideCompleted: true);
            Expect("stable", 250, Resolve("", a, true, 250), Docked);
            Begin("", a, autoHideCompleted: false);
            for (var offset = 250; offset <= 1750; offset += 250)
                Expect("auto-hide pending", offset, Resolve("", a, true, offset), Settling);
            Expect("auto-hide pending", 2000, Resolve("", a, true, 2000), Docked);
            Begin("", a, autoHideCompleted: true);
            Expect("moved", 250, Resolve("", b, true, 250), Settling);
            Expect("moved", 500, Resolve("", b, true, 500), Docked);
            Begin("", a, autoHideCompleted: true);
            Expect("non-sample geometry", 100, Resolve("", a, false, 100), Settling);
            Expect("non-sample geometry", 250, Resolve("", a, true, 250), Docked);
            Begin("", a, autoHideCompleted: false);
            Expect("auto-hide completes", 250, Resolve("", a, true, 250), Settling);
            _autoHideQueryCompleted.SetValue(_tracker, true);
            Expect("auto-hide completes", 400, Resolve("", a, false, 400), Settling);
            Expect("auto-hide completes", 500, Resolve("", a, true, 500), Docked);

            // Geometry that never repeats must not keep the widget hidden past 10 s.
            Begin("", Dock(0), autoHideCompleted: true);
            for (var step = 1; step < 40; step++)
                Expect("unstable geometry", step * 250, Resolve("", Dock(step), true, step * 250), Settling);
            Expect("unstable geometry", 10000, Resolve("", Dock(40), true, 10000), Docked);

            // A settle that ends on a covered taskbar reports fullscreen, never settling.
            Begin("fullscreen", a, autoHideCompleted: true);
            Expect("fullscreen settle", 250, Resolve("fullscreen", a, true, 250), Fullscreen);
            Begin("", a, autoHideCompleted: true);
            Expect("fullscreen after dockable", 250, Resolve("fullscreen", a, true, 250), Fullscreen);

            // Outside settling every reason resolves at once and none reports settling.
            _settling.SetValue(_tracker, false);
            foreach (var reason in FallbackReasons)
                Expect("outside settling", 0, Resolve(reason, null, true, 0), Fallback(reason));
            Expect("outside settling", 0, Resolve("", a, true, 0), Docked);
            Expect("outside settling", 0, Resolve("fullscreen", a, true, 0), Fullscreen);

            // Leaving a fallback for any dockable reading settles first, covered or not.
            ExpectLeavesFallback("Fallback", false, "", a, true);
            ExpectLeavesFallback("Fallback", false, "fullscreen", a, true);
            foreach (var reason in FallbackReasons) ExpectLeavesFallback("Fallback", false, reason, null, false);
            ExpectLeavesFallback("Docked", false, "", a, false);
            ExpectLeavesFallback("Suppressed", false, "", a, false);
            ExpectLeavesFallback("Inactive", false, "", a, false);
            ExpectLeavesFallback("Fallback", true, "", a, false);
        }

        public void Dispose() => _tracker.Dispose();

        private static FieldInfo Field(Type type, string name) =>
            type.GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new MissingFieldException(type.FullName, name);

        private static string Fallback(string reason) => $"Fallback({reason})";

        // Mirrors BeginSettling: the first evaluation is the first sample, for geometry and hard fallbacks.
        private void Begin(string reason, object? candidate, bool autoHideCompleted)
        {
            _settling.SetValue(_tracker, true);
            _settleStartedAt.SetValue(_tracker, Start);
            _settleSample.SetValue(_tracker, candidate);
            _settleFallbackReason.SetValue(_tracker,
                (bool)_isHardFallback.Invoke(null, [reason])! ? reason : null);
            _settleFallbackSince.SetValue(_tracker, Start);
            _autoHideQueryCompleted.SetValue(_tracker, autoHideCompleted);
        }

        private string Resolve(string reason, object? candidate, bool sample, long offset)
        {
            var state = _resolveState.Invoke(_tracker, [Evaluation(reason, candidate), sample, Start + offset])
                        ?? throw new InvalidOperationException("TaskbarTracker.ResolveState returned null");
            var status = Get(state, "Status")?.ToString();
            var result = $"{status}({Get(state, "Reason")})";
            if (status == "Docked" && !Equals(Get(state, "Dock"), candidate)) result += " wrong-dock";
            if ((bool)_settling.GetValue(_tracker)!) result += " settling";
            return result;
        }

        private void Expect(string scenario, long offset, string actual, string expected)
        {
            Count++;
            if (actual != expected) _failures.Add($"{scenario} at +{offset} ms: {actual}, expected {expected}");
        }

        private void ExpectLeavesFallback(string status, bool settling, string reason, object? candidate,
            bool expected)
        {
            Count++;
            var actual = (bool)_leavesFallback.Invoke(null,
                [Enum.Parse(_statusType, status), settling, Evaluation(reason, candidate)])!;
            if (actual != expected)
            {
                _failures.Add($"LeavesFallback({status}, settling={settling}, reason='{reason}') = {actual}, " +
                              $"expected {expected}");
            }
        }

        private object Evaluation(string reason, object? candidate) =>
            CreateByName(_evaluationType, new Dictionary<string, object?>
            {
                ["Reason"] = reason,
                ["Candidate"] = candidate,
                ["TaskbarTopmost"] = true,
                ["AutoHide"] = false
            });

        private object Dock(int leftPixels) =>
            CreateByName(_dockType, new Dictionary<string, object?>
            {
                ["BandLeftPixels"] = leftPixels,
                ["BandTopPixels"] = TaskbarBandTopPixels,
                ["BandRightPixels"] = TaskbarBandRightPixels,
                ["BandBottomPixels"] = TaskbarBandTopPixels + 48,
                ["AnchorRightPixels"] = TaskbarAnchorRightPixels,
                ["LightTaskbar"] = false,
                ["HighContrast"] = false
            });
    }

    private sealed class StateFactory
    {
        private readonly Type _statusType;
        private readonly Type _sourceType;
        private readonly ConstructorInfo _limitConstructor;
        private readonly ConstructorInfo _snapshotConstructor;
        private readonly ConstructorInfo _codexSnapshotConstructor;
        private readonly ConstructorInfo _stateConstructor;

        internal StateFactory(Type statusType, Type limitType, Type snapshotType, Type sourceType,
            Type codexSnapshotType, Type stateType)
        {
            _statusType = statusType;
            _sourceType = sourceType;
            _limitConstructor = Constructor(limitType, 2);
            _snapshotConstructor = Constructor(snapshotType, 5);
            _codexSnapshotConstructor = Constructor(codexSnapshotType, 5);
            _stateConstructor = Constructor(stateType, 10);
        }

        internal object Create(bool showClaude, bool showCodex)
        {
            var ready = Enum.Parse(_statusType, "Ready");
            var loading = Enum.Parse(_statusType, "Loading");
            var limit = _limitConstructor.Invoke([42d, null]);
            var claude = showClaude
                ? _snapshotConstructor.Invoke([limit, limit, limit, Enum.Parse(_sourceType, "ClaudeCode"), null])
                : null;
            var codex = showCodex
                ? _codexSnapshotConstructor.Invoke([limit, limit, null, null, null])
                : null;
            return _stateConstructor.Invoke([
                showClaude || showCodex ? ready : loading,
                claude,
                "probe",
                null,
                null,
                codex,
                showClaude ? ready : loading,
                showCodex ? ready : loading,
                "probe",
                "probe"
            ]);
        }

        private static ConstructorInfo Constructor(Type type, int parameterCount) =>
            type.GetConstructors(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
                .Single(candidate => candidate.GetParameters().Length == parameterCount);
    }

    private readonly record struct LayoutSnapshot(
        double Width,
        double Height,
        double DesiredHeight,
        IReadOnlyDictionary<string, ElementSnapshot> Elements)
    {
        internal bool IsEquivalentTo(LayoutSnapshot other) =>
            NearlyEqual(Width, other.Width) &&
            NearlyEqual(Height, other.Height) &&
            NearlyEqual(DesiredHeight, other.DesiredHeight) &&
            Elements.Count == other.Elements.Count &&
            Elements.All(pair => other.Elements.TryGetValue(pair.Key, out var element) &&
                                 pair.Value.IsEquivalentTo(element));

        internal bool HasExpectedProviderSplit(LayoutSnapshot twoRows, bool small) =>
            Width > twoRows.Width + HeightTolerance &&
            Height + HeightTolerance < twoRows.Height &&
            (small
                ? IsVisible("SmallPanel") && twoRows.IsVisible("SmallPanel") &&
                  IsVisible("SmallClaudePanel") && IsVisible("SmallCodexPanel") &&
                  twoRows.IsVisible("SmallClaudePanel") && twoRows.IsVisible("SmallCodexPanel") &&
                  Left("SmallClaudePanel") < Left("SmallCodexPanel") &&
                  twoRows.Top("SmallCodexPanel") < twoRows.Top("SmallClaudePanel")
                : IsVisible("CompactPanel") && !IsVisible("ComfortablePanel") &&
                  IsVisible("CompactFiveCard") && IsVisible("CompactCodexCard") &&
                  !twoRows.IsVisible("CompactPanel") && twoRows.IsVisible("ComfortablePanel") &&
                  twoRows.IsVisible("ComfortableCodexCard") && twoRows.IsVisible("MetricsPanel") &&
                  twoRows.IsVisible("ComfortableFiveCard") &&
                  twoRows.Top("ComfortableCodexCard") < twoRows.Top("MetricsPanel"));

        private bool IsVisible(string name) => Elements[name].Visibility == Visibility.Visible;
        private double Left(string name) => Elements[name].Bounds.Left;
        private double Top(string name) => Elements[name].Bounds.Top;

        private static bool NearlyEqual(double left, double right) =>
            Math.Abs(left - right) <= IdentityTolerance;

        public override string ToString() =>
            $"Width={Width:0.##}, Height={Height:0.##}, Desired={DesiredHeight:0.##}";
    }

    private readonly record struct ElementSnapshot(Visibility Visibility, Rect Bounds)
    {
        internal bool IsEquivalentTo(ElementSnapshot other) =>
            Visibility == other.Visibility &&
            (Visibility != Visibility.Visible ||
             NearlyEqual(Bounds.Left, other.Bounds.Left) &&
             NearlyEqual(Bounds.Top, other.Bounds.Top) &&
             NearlyEqual(Bounds.Width, other.Bounds.Width) &&
             NearlyEqual(Bounds.Height, other.Bounds.Height));

        private static bool NearlyEqual(double left, double right) =>
            Math.Abs(left - right) <= IdentityTolerance;
    }
}
