using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;
using Size = System.Windows.Size;

namespace ClaudeUsageTray;

// Shared by the widget calculator and the actual view; hiding progress removes
// the chart column, never the labels. Provider height stays equal in a pair.
internal readonly record struct OrbitSystemMetrics(double Chart, double Legend, double Row, double Font,
    double PaddingX, double PaddingY, double Gap = 10, double Heading = 18)
{
    internal const double ProviderGap = 12;
    internal double Width(bool progress) => Legend + (progress ? Chart + Gap : 0);
    internal double Height(bool progress) => Heading + Math.Max(Row * 3, progress ? Chart : 0);
    internal static OrbitSystemMetrics For(WidgetDensity density) => density switch
    {
        WidgetDensity.Small => new(64, 88, 18, 10, 7, 6),
        WidgetDensity.Comfortable => new(104, 110, 24, 12, 14, 10.5),
        _ => new(84, 98, 21, 11, 10, 8)
    };
}

internal sealed record OrbitMetric(string Label, OrbitBodyKind Body, UsageLimit? Limit,
    string? MissingLabel = null, string? MissingHint = null)
{
    // One normalized number owns text, sweep and marker position. Invalid source
    // values are unknown, not a zero reading or invalid WPF geometry.
    internal double? Value => Limit is not null && double.IsFinite(Limit.Percent)
        ? Math.Clamp(Limit.Percent, 0, 100) : null;
    internal string ValueText => Value is double value ? $"{value:0}%" : MissingLabel ?? "--%";
    internal string ResetText => MissingHint ?? (Limit?.ResetsAt is DateTimeOffset reset
        ? $"초기화 {reset.LocalDateTime:ddd HH:mm}" : "초기화 시간 미제공");

    internal static OrbitMetric[] Claude(ApplicationState state)
    {
        var snapshot = state.Snapshot;
        var unavailable = snapshot?.Fable is null && (snapshot?.Source == ClaudeUsageSource.ClaudeDesktop ||
            snapshot?.Source == ClaudeUsageSource.ClaudeCode && !snapshot.FableExpired);
        return [new("5시간", OrbitBodyKind.Mars, snapshot?.FiveHour),
            new("주간", OrbitBodyKind.Earth, snapshot?.Weekly),
            new("Fable", OrbitBodyKind.Venus, snapshot?.Fable, unavailable ? "미제공" : null,
                unavailable ? snapshot?.Source == ClaudeUsageSource.ClaudeDesktop
                    ? "Claude Code 로그인 필요" : "계정에 전용 한도 없음" : null)];
    }

    internal static OrbitMetric[] Codex(ApplicationState state, bool detailed)
    {
        var snapshot = state.CodexSnapshot;
        if (detailed || snapshot?.ShowSeparateFiveHour == true)
            return [new("5시간", OrbitBodyKind.Jupiter, snapshot?.FiveHour),
                new("주간", OrbitBodyKind.Saturn, snapshot?.Weekly)];
        return [new(snapshot?.HasWeeklyWindow == true ? "주간" : snapshot?.HasFiveHourWindow == true
            ? "5시간" : "사용량", snapshot?.HasWeeklyWindow != true && snapshot?.HasFiveHourWindow == true
            ? OrbitBodyKind.Jupiter : OrbitBodyKind.Saturn, snapshot?.DisplayLimit)];
    }
}

/// <summary>A shared-center system and its exact-value legend. No timers, network or saved state.</summary>
public sealed class OrbitSystemView : Grid
{
    internal void Update(OrbitMetric[] metrics, string provider, TraySettings settings, bool detailed = false, bool legendOnly = false)
    {
        Children.Clear();
        RowDefinitions.Clear();
        ColumnDefinitions.Clear();
        var size = OrbitSystemMetrics.For(settings.WidgetDensity);
        var showChart = settings.ShowProgressBars && !legendOnly;
        Width = detailed ? double.NaN : size.Width(showChart);
        Height = detailed ? double.NaN : size.Height(showChart);
        MinHeight = detailed && showChart ? 148 : 0;
        RowDefinitions.Add(new RowDefinition { Height = detailed ? new GridLength(0) : new GridLength(size.Heading) });
        RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var chartSize = detailed ? 144 : size.Chart;
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(showChart ? chartSize + size.Gap : 0) });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (!detailed)
        {
            var title = Text(provider, size.Font, "OrbitProviderText", true);
            SetColumnSpan(title, 2);
            Children.Add(title);
        }
        var chart = new OrbitSystemChart(metrics, settings.UseThresholdColors, !detailed)
        {
            Width = chartSize, Height = chartSize,
            HorizontalAlignment = System.Windows.HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = showChart ? Visibility.Visible : Visibility.Collapsed
        };
        SetRow(chart, 1);
        Children.Add(chart);
        var legend = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        SetRow(legend, 1);
        SetColumn(legend, 1);
        foreach (var metric in metrics)
        {
            var row = new Grid { MinHeight = detailed ? 48 : size.Row };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(14) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            if (detailed) row.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var icon = new OrbitBodyMarker { Body = metric.Body, Width = 11, Height = 11,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
            icon.SetResourceReference(OrbitBodyMarker.FillProperty, detailed ? "AccentBrush" : "WidgetAccentBrush");
            icon.SetResourceReference(OrbitBodyMarker.TrackProperty, "BorderBrush");
            row.Children.Add(icon);
            var label = Text(metric.Label, detailed ? 11 : size.Font, "OrbitLegendText", !detailed);
            SetColumn(label, 1);
            row.Children.Add(label);
            var value = Text(metric.ValueText, detailed ? 12 : size.Font, "OrbitValueText", !detailed);
            value.SetResourceReference(TextBlock.ForegroundProperty, ToneKey(metric.Value, settings.UseThresholdColors, !detailed));
            value.Margin = new Thickness(4, 0, 0, 0);
            SetColumn(value, 2);
            row.Children.Add(value);
            if (detailed)
            {
                var reset = Text(metric.ResetText, 10, "OrbitLegendText", false);
                reset.TextWrapping = TextWrapping.Wrap;
                reset.Margin = new Thickness(0, 3, 0, 8);
                SetRow(reset, 1);
                SetColumn(reset, 1);
                SetColumnSpan(reset, 2);
                row.Children.Add(reset);
            }
            row.ToolTip = $"{provider} · {metric.Label} {metric.ValueText}\n{metric.ResetText}";
            AutomationProperties.SetName(row, $"{provider} {metric.Label} {metric.ValueText}, {metric.ResetText}");
            legend.Children.Add(row);
        }
        Children.Add(legend);
    }

    private TextBlock Text(string text, double fontSize, string style, bool widget)
    {
        var element = new TextBlock { Text = text, FontSize = fontSize, VerticalAlignment = VerticalAlignment.Center };
        element.SetResourceReference(StyleProperty, style);
        element.SetResourceReference(TextBlock.FontFamilyProperty, widget ? "WidgetFontFamily" : "AppFontFamily");
        if (widget) element.SetResourceReference(TextBlock.ForegroundProperty,
            style == "OrbitLegendText" ? "WidgetMutedTextBrush" : "WidgetTextBrush");
        return element;
    }

    internal static string ToneKey(double? value, bool thresholds, bool widget) =>
        thresholds && value >= 90 ? "DangerBrush" : thresholds && value >= 70 ? "WarningBrush"
        : widget ? "WidgetMetricTextBrush" : "TextBrush";
}

internal sealed class OrbitSystemChart(OrbitMetric[] metrics, bool thresholds, bool widget, bool solar = false) : FrameworkElement
{
    internal IReadOnlyList<OrbitMetric> Metrics => metrics;

    internal static Point Position(Point center, double radius, double value)
    {
        var radians = (-90 + Math.Clamp(value, 0, 100) * 3.6) * Math.PI / 180;
        return new Point(center.X + radius * Math.Cos(radians), center.Y + radius * Math.Sin(radians));
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var diameter = Math.Min(ActualWidth, ActualHeight);
        if (diameter <= 0 || metrics.Length == 0) return;
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var marker = Math.Clamp(diameter / 22, 2.8, solar ? 9 : 5.5);
        var outer = diameter / 2 - marker * 1.85 - 2;
        var inner = metrics.Length == 1 ? outer : outer * (solar && metrics.Length > 3 ? 0.25 : 0.42);
        var track = Resolve(widget ? "WidgetTrackBrush" : "BorderBrush");
        var accent = Resolve(widget ? "WidgetAccentBrush" : "AccentBrush");
        if (solar)
        {
            dc.DrawEllipse(Resolve("OrbitSunCoreBrush"), null, center, 10, 10);
            dc.DrawEllipse(Resolve("OrbitSunBrush"), null, center, 6, 6);
        }
        else
        {
            dc.DrawEllipse(null, new Pen(track, 1), center, 5, 5);
            dc.DrawEllipse(accent, null, center, 2, 2);
        }
        for (var i = 0; i < metrics.Length; i++)
        {
            var metric = metrics[i];
            var radius = metrics.Length == 1 ? outer : inner + (outer - inner) * i / (metrics.Length - 1);
            var pen = new Pen(track, diameter < 90 ? 1 : 1.4);
            if (metric.Value is null) pen.DashStyle = DashStyles.Dot;
            dc.DrawEllipse(null, pen, center, radius, radius);
            if (metric.Value is not double value) continue;
            // The planet's color identifies the orbit; warning colors still override it.
            var color = thresholds && value >= 70
                ? Resolve(value >= 90 ? "DangerBrush" : "WarningBrush")
                : Resolve(metric.Body switch
                {
                    OrbitBodyKind.Mars => "OrbitMarsProgressBrush",
                    OrbitBodyKind.Venus => "OrbitVenusProgressBrush",
                    OrbitBodyKind.Jupiter => "OrbitJupiterProgressBrush",
                    OrbitBodyKind.Moon => "OrbitMoonProgressBrush",
                    OrbitBodyKind.Earth => "OrbitEarthProgressBrush",
                    OrbitBodyKind.Sun => "OrbitSunProgressBrush",
                    _ => "OrbitSaturnProgressBrush"
                });
            var progress = new Pen(color, diameter < 90 ? 2 : 2.5)
                { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            if (value >= 100) dc.DrawEllipse(null, progress, center, radius, radius);
            else if (value > 0)
            {
                var figure = new PathFigure { StartPoint = Position(center, radius, 0) };
                figure.Segments.Add(new ArcSegment(Position(center, radius, value), new Size(radius, radius),
                    0, value > 50, SweepDirection.Clockwise, true));
                dc.DrawGeometry(null, progress, new PathGeometry([figure]));
            }
            // 0% deliberately has a planet at twelve o'clock, but no filled arc.
            OrbitBodyPainter.Draw(dc, Position(center, radius, value), marker, metric.Body, accent, track,
                key => TryFindResource(key) as Brush);
        }
    }

    private Brush Resolve(string key) => TryFindResource(key) as Brush ?? System.Windows.Media.Brushes.Gray;
}
