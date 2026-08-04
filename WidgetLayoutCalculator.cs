namespace ClaudeUsageTray;

internal readonly record struct WidgetLayoutRequest(
    WidgetDensity Density,
    WidgetLayout Layout,
    WidgetVisualTheme Theme,
    bool ShowClaude,
    bool ShowCodex,
    bool ShowProgressBars);

internal readonly record struct WidgetLayoutMetrics(
    double Width,
    double Height,
    double CompactGap,
    double ComfortableGap,
    double ProviderTop,
    double ProviderGap,
    double SmallCodexMarginLeft,
    double SmallCodexMarginTop);

/// <summary>
/// Calculates widget geometry without touching WPF controls so every service and
/// density combination shares one auditable set of sizing rules.
/// </summary>
internal static class WidgetLayoutCalculator
{
    internal static WidgetLayoutMetrics Calculate(WidgetLayoutRequest request)
    {
        var small = request.Density == WidgetDensity.Small;
        var comfortable = request.Density == WidgetDensity.Comfortable;
        var compact = request.Density == WidgetDensity.Compact;
        var singleRow = request.Layout == WidgetLayout.SingleRow;
        var themed = ThemeManager.UsesThemedChrome(request.Theme);
        var providerCount = (request.ShowClaude ? 1 : 0) + (request.ShowCodex ? 1 : 0);

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
        var codexMarginTop = request.ShowClaude && request.ShowCodex && !singleRow ? 8 : 0;

        var (width, height) = CalculateWindowSize(request, providerCount, small, comfortable, singleRow, themed);
        return new WidgetLayoutMetrics(width, height, compactGap, comfortableGap, providerTop, providerGap,
            codexMarginLeft, codexMarginTop);
    }

    private static (double Width, double Height) CalculateWindowSize(WidgetLayoutRequest request,
        int providerCount, bool small, bool comfortable, bool singleRow, bool themed)
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
            return (width, height);
        }

        var themeBarExtra = request.Theme switch
        {
            WidgetVisualTheme.RetroNight => 10,
            WidgetVisualTheme.FluentGlass => 14,
            WidgetVisualTheme.TerminalMono => 22,
            WidgetVisualTheme.Orbit => 44,
            WidgetVisualTheme.PaperInk => 10,
            _ => 0
        };

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
            var height = request.ShowProgressBars ? comfortable ? 56 : 48 : comfortable ? 44 : 38;
            if (themed) height += request.ShowProgressBars ? themeBarExtra : 1;
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
        var hiddenBarReduction = request.ShowProgressBars ? 0 : providerCount * (comfortable ? 11 : 9);
        var heightTwoRows = (providerCount == 2
            ? comfortable ? 104 : 88
            : comfortable ? 68 : 58) - hiddenBarReduction;
        if (themed)
            heightTwoRows += (request.ShowProgressBars ? providerCount * Math.Max(1, themeBarExtra - 2) : 0)
                + 2;
        return (widthTwoRows, heightTwoRows);
    }
}
