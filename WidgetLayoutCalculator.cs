namespace ClaudeUsageTray;

internal readonly record struct WidgetLayoutRequest(
    WidgetDensity Density,
    WidgetLayout Layout,
    WidgetVisualTheme Theme,
    bool ShowClaude,
    bool ShowCodex,
    bool ShowProgressBars,
    bool InTaskbar = false,
    double TaskbarBandHeight = WidgetLayoutCalculator.DefaultTaskbarBandHeight);

/// <summary>
/// Geometry of the in-taskbar overlay. Every length is in DIPs and is applied
/// by UsageWidgetWindow to the TaskbarPanel cells without further arithmetic.
/// </summary>
internal readonly record struct TaskbarLayoutMetrics(
    double CellWidth,
    double CellGap,
    double ProviderGap,
    double PaddingX,
    double PaddingY,
    double LabelLineHeight,
    double ValueLineHeight,
    double ProgressHeight,
    double ProgressTopMargin,
    double ProgressSideMargin,
    bool ProgressVisible,
    double AnchorGap);

internal readonly record struct WidgetLayoutMetrics(
    double Width,
    double Height,
    double CompactGap,
    double ComfortableGap,
    double ProviderTop,
    double ProviderGap,
    double SmallCodexMarginLeft,
    double SmallClaudeMarginTop,
    WidgetLayout EffectiveLayout,
    TaskbarLayoutMetrics? Taskbar = null);

/// <summary>
/// Calculates widget geometry without touching WPF controls so every service and
/// density combination shares one auditable set of sizing rules.
/// </summary>
internal static class WidgetLayoutCalculator
{
    internal const double DefaultTaskbarBandHeight = 48;
    internal const double MinimumTaskbarBandHeight = 32;

    // In-taskbar overlay geometry. It ignores density, row layout and visual
    // theme so the overlay keeps one shape inside every supported band height.
    private const double TaskbarCellWidth = 38;
    private const double TaskbarCellGap = 4;
    private const double TaskbarProviderGap = 8;
    private const double TaskbarPaddingX = 6;
    private const double TaskbarPaddingY = 2;
    private const double TaskbarLabelLineHeight = 12;
    private const double TaskbarValueLineHeight = 14;
    private const double TaskbarProgressHeight = 3;
    private const double TaskbarProgressTopMargin = 2;
    private const double TaskbarProgressSideMargin = 3;
    private const double TaskbarAnchorGap = 4;
    private const double TaskbarClippingGuard = 1;

    internal static WidgetLayoutMetrics Calculate(WidgetLayoutRequest request)
    {
        var small = request.Density == WidgetDensity.Small;
        var comfortable = request.Density == WidgetDensity.Comfortable;
        var compact = request.Density == WidgetDensity.Compact;
        var themed = ThemeManager.UsesThemedChrome(request.Theme);
        var providerCount = (request.ShowClaude ? 1 : 0) + (request.ShowCodex ? 1 : 0);
        // TwoRows separates Codex and Claude. With fewer than two visible
        // providers it must be visually identical to SingleRow. The in-taskbar
        // overlay is always a single row.
        var effectiveLayout = !request.InTaskbar && request.Layout == WidgetLayout.TwoRows && providerCount == 2
            ? WidgetLayout.TwoRows
            : WidgetLayout.SingleRow;
        var singleRow = effectiveLayout == WidgetLayout.SingleRow;

        var compactGap = small ? 6 : request.Theme switch
        {
            WidgetVisualTheme.RetroNight => 6,
            WidgetVisualTheme.FluentGlass => 8,
            WidgetVisualTheme.TerminalMono => 5,
            WidgetVisualTheme.Orbit => 8,
            WidgetVisualTheme.PaperInk => 12,
            _ => 10
        };
        var comfortableGap = request.Theme switch
        {
            WidgetVisualTheme.TerminalMono => 8,
            WidgetVisualTheme.PaperInk => 20,
            _ => 14
        };
        const double providerTop = 0;
        var providerGap = compact ? 10 : 12;
        var codexMarginLeft = request.ShowClaude && request.ShowCodex && singleRow ? 8 : 0;
        var claudeMarginTop = request.ShowClaude && request.ShowCodex && !singleRow ? 8 : 0;

        if (request.InTaskbar)
        {
            var (taskbarWidth, taskbarHeight, taskbar) = CalculateTaskbarSize(request);
            return new WidgetLayoutMetrics(taskbarWidth, taskbarHeight, compactGap, comfortableGap, providerTop,
                providerGap, codexMarginLeft, claudeMarginTop, effectiveLayout, taskbar);
        }

        var (width, height) = CalculateWindowSize(
            request, providerCount, small, comfortable, singleRow, themed, providerGap);
        return new WidgetLayoutMetrics(width, height, compactGap, comfortableGap, providerTop, providerGap,
            codexMarginLeft, claudeMarginTop, effectiveLayout);
    }

    /// <summary>
    /// Sizes the in-taskbar overlay: three Claude cells separated by the cell
    /// gap, one Codex cell after the provider gap, and one message cell when no
    /// provider is visible. Hidden providers contribute neither a cell nor a gap.
    /// The progress row is dropped when the band cannot keep one DIP above and
    /// below it, so the height fits every band of at least MinimumTaskbarBandHeight.
    /// </summary>
    private static (double Width, double Height, TaskbarLayoutMetrics Metrics) CalculateTaskbarSize(
        WidgetLayoutRequest request)
    {
        var claudeCells = request.ShowClaude ? 3 : 0;
        var codexCells = request.ShowCodex ? 1 : 0;
        var cells = claudeCells + codexCells;
        var contentWidth = cells == 0
            ? TaskbarCellWidth
            : cells * TaskbarCellWidth + Math.Max(0, claudeCells - 1) * TaskbarCellGap +
              (request.ShowClaude && request.ShowCodex ? TaskbarProviderGap : 0);
        var width = 2 * TaskbarPaddingX + contentWidth;

        var baseHeight = TaskbarLabelLineHeight + TaskbarValueLineHeight + 2 * TaskbarPaddingY +
                         TaskbarClippingGuard;
        var heightWithProgress = baseHeight + TaskbarProgressTopMargin + TaskbarProgressHeight;
        var progressVisible = request.ShowProgressBars && cells > 0 &&
                              request.TaskbarBandHeight >= heightWithProgress + 2;
        var metrics = new TaskbarLayoutMetrics(
            TaskbarCellWidth,
            TaskbarCellGap,
            TaskbarProviderGap,
            TaskbarPaddingX,
            TaskbarPaddingY,
            TaskbarLabelLineHeight,
            TaskbarValueLineHeight,
            TaskbarProgressHeight,
            TaskbarProgressTopMargin,
            TaskbarProgressSideMargin,
            progressVisible,
            TaskbarAnchorGap);
        return (width, progressVisible ? heightWithProgress : baseHeight, metrics);
    }

    private static (double Width, double Height) CalculateWindowSize(WidgetLayoutRequest request,
        int providerCount, bool small, bool comfortable, bool singleRow, bool themed, double providerGap)
    {
        if (providerCount == 0)
            return (small ? 250 : comfortable ? 360 : 300, small ? 34 : comfortable ? 48 : 40);

        if (small)
        {
            var width = request.ShowClaude ? 168 : 72;
            if (singleRow && request.ShowClaude && request.ShowCodex) width = 224;
            width -= 10;

            var height = singleRow ? 60 : providerCount == 2 ? 110 : 60;
            if (themed)
            {
                var chromeExtra = ThemeManager.UsesAngularChrome(request.Theme) ? 2
                    : request.Theme is WidgetVisualTheme.FluentGlass or WidgetVisualTheme.Orbit ? 4 : 1;
                width += chromeExtra;
                height += chromeExtra;
            }
            // Keep two DIPs beyond the measured content boundary. Modern's
            // two-provider vertical stack previously missed its chrome by two
            // additional DIPs because it has no themed chrome allowance.
            height += 2;
            if (!themed && !singleRow && providerCount == 2) height += 2;
            return (width, height);
        }

        var vertical = LinearHeightMetrics.For(request.Theme);
        var outerChromeHeight = comfortable ? vertical.ComfortableOuterChromeHeight : vertical.CompactOuterChromeHeight;
        var rowWithoutProgress = comfortable ? vertical.ComfortableRowWithoutProgress : vertical.CompactRowWithoutProgress;
        var progressFootprint = request.ShowProgressBars
            ? vertical.ProgressVisualHeight + (comfortable ? 7 : 5)
            : 0;
        var rowHeight = rowWithoutProgress + progressFootprint;
        const double clippingGuard = 2;

        if (singleRow)
        {
            var baseWidth = comfortable
                ? request.ShowClaude && request.ShowCodex ? 600 : request.ShowClaude ? 456 : 240
                : request.ShowClaude && request.ShowCodex ? 520 : request.ShowClaude ? 378 : 190;
            if (request.ShowCodex) baseWidth -= comfortable ? 40 : 28;

            // Compact and Comfortable previously spent too much horizontal space per metric.
            // Reduce the content baseline by 25%, while preserving theme-specific chrome room.
            var width = Math.Round(baseWidth * 0.75);
            var visibleMetricCount = (request.ShowClaude ? 3 : 0) + (request.ShowCodex ? 1 : 0);
            width += visibleMetricCount * (request.Theme switch
            {
                WidgetVisualTheme.RetroNight => 10,
                WidgetVisualTheme.FluentGlass => 16,
                WidgetVisualTheme.TerminalMono => 14,
                WidgetVisualTheme.Orbit => 18,
                WidgetVisualTheme.PaperInk => 7,
                _ => 0
            });
            var height = outerChromeHeight + rowHeight + clippingGuard;
            return (width, height);
        }

        var baseWidthTwoRows = comfortable
            ? request.ShowClaude ? 480 : 340
            : request.ShowClaude ? 400 : 260;
        if (!request.ShowClaude && request.ShowCodex) baseWidthTwoRows -= comfortable ? 48 : 36;
        var widthTwoRows = Math.Round(baseWidthTwoRows * 0.75);
        widthTwoRows += request.Theme switch
        {
            WidgetVisualTheme.RetroNight => 20,
            WidgetVisualTheme.FluentGlass => 42,
            WidgetVisualTheme.TerminalMono => 32,
            WidgetVisualTheme.Orbit => 48,
            WidgetVisualTheme.PaperInk => 18,
            _ => 0
        };
        var heightTwoRows = outerChromeHeight + rowHeight * providerCount +
                            Math.Max(0, providerCount - 1) * providerGap + clippingGuard;
        return (widthTwoRows, heightTwoRows);
    }

    /// <summary>
    /// Vertical geometry shared by every linear widget layout. Values include
    /// the root chrome and the still-visible metric card/text row, while the
    /// progress visual is kept separate so hiding it removes only its real
    /// footprint. The two-DIP guard in CalculateWindowSize absorbs layout
    /// rounding at fractional display scales.
    /// </summary>
    private readonly record struct LinearHeightMetrics(
        double CompactOuterChromeHeight,
        double ComfortableOuterChromeHeight,
        double CompactRowWithoutProgress,
        double ComfortableRowWithoutProgress,
        double ProgressVisualHeight)
    {
        internal static LinearHeightMetrics For(WidgetVisualTheme theme) => theme switch
        {
            WidgetVisualTheme.RetroNight => new(20, 25, 25, 30, 8),
            WidgetVisualTheme.FluentGlass => new(18, 23, 31, 36, 6),
            WidgetVisualTheme.TerminalMono => new(18, 23, 28, 33, 16),
            WidgetVisualTheme.Orbit => new(18, 23, 34, 40, 32),
            WidgetVisualTheme.PaperInk => new(18, 23, 24, 28, 12),
            _ => new(20, 26, 16, 17, 4)
        };
    }
}
