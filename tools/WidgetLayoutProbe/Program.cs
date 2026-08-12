using System.Reflection;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shell;

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
            window.Close();
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

        foreach (var failure in clippingFailures) Console.Error.WriteLine($"CLIP {failure}");
        foreach (var failure in layoutFailures) Console.Error.WriteLine($"LAYOUT {failure}");
        foreach (var failure in frameFailures) Console.Error.WriteLine($"FRAME {failure}");
        Console.WriteLine($"Widget layout matrix: {count} checked, {clippingFailures.Count} clipped, " +
                          $"{invariantCount} zero/one-provider invariants, {splitCount} two-provider splits, " +
                          $"{autoDetectCount} auto-detection equivalences, " +
                          $"{layoutFailures.Count} mismatched");
        Console.WriteLine($"Settings frame matrix: {frameStateCount} checked, {frameFailures.Count} invalid");
        return clippingFailures.Count == 0 && layoutFailures.Count == 0 && frameFailures.Count == 0 ? 0 : 1;
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

    private sealed record ServiceScenario(string Name, string Mode, bool ShowClaude, bool ShowCodex);

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
